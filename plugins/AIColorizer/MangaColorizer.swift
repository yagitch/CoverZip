import AppKit
import CoreML
import os.log

/// 漫画用の独立プラグイン。全ページは512角、頭部だけを別モデルで解析する。
@objc(CZAIColorizerPlugin)
public final class MangaColorizerPlugin: NSObject {
    private var generator: UnsafeMutableRawPointer?
    private var detector: UnsafeMutableRawPointer?
    private var foreground: UnsafeMutableRawPointer?
    private var parser: MLModel?
    private let side = 512
    private let skin: [Float] = [0.96, 0.76, 0.65]
    private let fast = AIColorizerPlugin()
    private var usesFastModel = false
    @objc public func selectModel(_ model: NSString) { usesFastModel = model == "fast" }
    @objc public func inputSideLength() -> NSNumber { usesFastModel ? 256 : 512 }

    deinit {
        for model in [generator, detector, foreground] { if let model { cz_manga_destroy(model) } }
    }

    private func load() throws {
        let bundle = Bundle(for: Self.self)
        func model(_ name: String) throws -> UnsafeMutableRawPointer {
            guard let url = bundle.url(forResource: name, withExtension: "onnx"),
                  let result = cz_manga_create(url.path, 1) else { throw failure("モデルを読み込めません: \(name)") }
            return result
        }
        if generator == nil { generator = try model("generator512") }
        if detector == nil { detector = try model("head") }
        if foreground == nil { foreground = try model("foreground-fp16") }
        if parser == nil {
            guard let url = bundle.url(forResource: "Parts", withExtension: "mlmodelc") else { throw failure("Partsがありません") }
            let config = MLModelConfiguration(); config.computeUnits = .cpuAndGPU
            parser = try MLModel(contentsOf: url, configuration: config)
        }
    }

    @objc public func colorizeBGRA(_ input: NSData) -> NSData? {
        if usesFastModel { return fast.colorizeBGRA(input) }
        guard input.length == side * side * 4 else { return nil }
        do {
            try load()
            let start = Date()
            guard let sourceImage = image(input as Data, side: side) else { return nil }
            let rgb = try tensor(sourceImage, side: side)
            let area = side * side
            var request = [Float](repeating: 0, count: area * 5)
            for p in 0..<area { request[p] = rgb[p] * 0.299 + rgb[area+p] * 0.587 + rgb[area*2+p] * 0.114 }
            var (result, shape) = try run(generator!, request, [1, 5, 512, 512])
            guard shape == [1, 3, 512, 512], let base = image(bytes(result), side: side) else { throw failure("生成画像の形式が不正です") }
            let (heads, headShape) = try run(detector!, tensor(sourceImage, side: 640), [1, 3, 640, 640])
            let boxes = try headBoxes(heads, shape: headShape)
            var skinMask = [Float](repeating: 0, count: area)
            var guidedHeads = 0
            for box in boxes {
                guard let crop = base.cropping(to: box) else { continue }
                let cropRGB = try tensor(crop, side: 512)
                let normalized = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32)
                let pointer = normalized.dataPointer.assumingMemoryBound(to: Float.self)
                let means: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
                for c in 0..<3 { for p in 0..<area { pointer[c*area+p] = (cropRGB[c*area+p] - means[c]) / std[c] } }
                let prediction = try parser!.prediction(from: MLDictionaryFeatureProvider(dictionary: ["normalized_rgb": normalized]))
                guard let labels = prediction.featureValue(for: "labels")?.multiArrayValue,
                      labels.count == area, labels.dataType == .int32 else { throw failure("パーツ出力が不正です") }
                let parts = labels.dataPointer.assumingMemoryBound(to: Int32.self)
                var skinCount = 0, eyeCount = 0
                for p in 0..<area {
                    if isSkin(parts[p]) { skinCount += 1 }
                    if parts[p] == 4 || parts[p] == 5 { eyeCount += 1 }
                }
                // 顔として不確かな領域や、背景を肌とするような極端なマスクは適用しない。
                guard skinCount > area / 100, skinCount < area * 3 / 4, eyeCount > 10 else { continue }
                let (mask, maskShape) = try run(foreground!, tensor(crop, side: 1024), [1, 3, 1024, 1024])
                guard maskShape == [1, 1, 1024, 1024] else { throw failure("前景出力が不正です") }
                for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) {
                    let cx = min(511, Int(Double(x - Int(box.minX)) * 512 / box.width))
                    let cy = min(511, Int(Double(y - Int(box.minY)) * 512 / box.height))
                    let p = y * side + x
                    let alpha = mask[(cy*2)*1024+cx*2]
                    guard isSkin(parts[cy*512+cx]), alpha > 0.7, request[p] > 0.22 else { continue }
                    skinMask[p] = max(skinMask[p], min(1, (alpha - 0.7) / 0.3))
                    if x % 8 == 0 && y % 8 == 0 {
                        for c in 0..<3 { request[(c+1)*area+p] = skin[c]*2-1 }
                        request[4*area+p] = 1
                    }
                }}
                guidedHeads += 1
            }
            if guidedHeads > 0 {
                (result, shape) = try run(generator!, request, [1, 5, 512, 512])
                guard shape == [1, 3, 512, 512] else { throw failure("再生成画像の形式が不正です") }
                // 肌のマスク内だけを穏やかに補正。明暗・線画は呼び出し側で原画から復元する。
                for p in 0..<area where skinMask[p] > 0 {
                    let amount = skinMask[p] * 0.45
                    for c in 0..<3 { result[c*area+p] = result[c*area+p] * (1-amount) + skin[c] * amount }
                }
            }
            NSLog("[Manga] heads=%d guided=%d seconds=%.3f", boxes.count, guidedHeads, Date().timeIntervalSince(start))
            return bytes(result) as NSData
        } catch {
            os_log("[Manga] 着色失敗: %{public}@", type: .error, error.localizedDescription)
            return nil
        }
    }

    private func isSkin(_ label: Int32) -> Bool { label == 1 || label == 7 || label == 8 || label == 10 }
    private func failure(_ message: String) -> NSError { NSError(domain: "CoverZipManga", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    private func run(_ model: UnsafeMutableRawPointer, _ input: [Float], _ shape: [Int64]) throws -> ([Float], [Int64]) {
        var output = [Float](repeating: 0, count: 3 * 1024 * 1024)
        var dimensions = [Int64](repeating: 0, count: 8), rank: Int32 = 0
        let count = cz_manga_run(model, input, shape, Int32(shape.count), &output, Int64(output.count), &dimensions, &rank)
        guard count > 0 else { throw failure("ONNXの推論に失敗しました") }
        output.removeSubrange(Int(count)..<output.count)
        return (output, Array(dimensions.prefix(Int(rank))))
    }

    private func image(_ data: Data, side: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side*4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func tensor(_ image: CGImage, side: Int) throws -> [Float] {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side*4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let data = context.data else { throw failure("縮小画像を確保できません") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bytes = data.assumingMemoryBound(to: UInt8.self), area = side*side
        var result = [Float](repeating: 0, count: area*3)
        for p in 0..<area { for c in 0..<3 { result[c*area+p] = Float(bytes[p*4+2-c])/255 } }
        return result
    }

    private func bytes(_ rgb: [Float]) -> Data {
        let area = side*side
        var result = Data(count: area*4)
        result.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let out = raw.bindMemory(to: UInt8.self)
            for p in 0..<area {
                for c in 0..<3 {
                    let value = rgb[c*area+p]
                    out[p*4+2-c] = UInt8(value.isFinite ? max(0, min(255, value*255)) : 0)
                }
                out[p*4+3] = 255
            }
        }
        return result
    }

    private func headBoxes(_ output: [Float], shape: [Int64]) throws -> [CGRect] {
        guard shape.count == 3, shape[0] == 1, shape[1] == 5 else { throw failure("頭部検出の形式が未対応: \(shape)") }
        let count = Int(shape[2])
        var candidates: [(CGRect, Float)] = []
        for i in 0..<count where output[4*count+i] > 0.4 {
            let cx = CGFloat(output[i])*0.8, cy = CGFloat(output[count+i])*0.8
            let w = CGFloat(output[2*count+i])*0.8, h = CGFloat(output[3*count+i])*0.8
            guard cx.isFinite, cy.isFinite, w.isFinite, h.isFinite, w >= 12, h >= 12 else { continue }
            let rect = CGRect(x: cx-w/2, y: cy-h/2, width: w, height: h).integral.intersection(CGRect(x: 0, y: 0, width: 512, height: 512))
            if !rect.isNull && rect.width >= 12 && rect.height >= 12 { candidates.append((rect, output[4*count+i])) }
        }
        var result: [CGRect] = []
        for (rect, _) in candidates.sorted(by: { $0.1 > $1.1 }) {
            if result.contains(where: { existing in
                let intersection = rect.intersection(existing)
                let area = intersection.isNull ? 0 : intersection.width*intersection.height
                return area / (rect.width*rect.height + existing.width*existing.height - area) > 0.7
            }) { continue }
            result.append(rect)
            if result.count == 6 { break }
        }
        return result
    }
}
