import AppKit
import os.log

/// 漫画用の独立プラグイン。顔・胴体・背景に同じ色バランスを適用する。
@objc(CZAIColorizerPlugin)
public final class MangaColorizerPlugin: NSObject {
    private var generator: UnsafeMutableRawPointer?
    private let side = 512
    private var skin: [Float] = [0.96, 0.76, 0.65]
    private var skinStrength: Float = 0.45
    @objc public func configureSkin(_ options: NSArray) {
        guard let values = options as? [NSNumber], values.count == 4,
              values.allSatisfy({ $0.doubleValue.isFinite && (0...1).contains($0.doubleValue) }) else { return }
        skin = values.prefix(3).map(\.floatValue)
        skinStrength = values[3].floatValue
    }
    private let fast = AIColorizerPlugin()
    private var usesFastModel = false
    @objc public func selectModel(_ model: NSString) { usesFastModel = model == "fast" }
    @objc public func inputSideLength() -> NSNumber { usesFastModel ? 256 : 512 }

    deinit {
        for model in [generator] { if let model { cz_manga_destroy(model) } }
    }

    private func load() throws {
        let bundle = Bundle(for: Self.self)
        func model(_ name: String) throws -> UnsafeMutableRawPointer {
            guard let url = bundle.url(forResource: name, withExtension: "onnx"),
                  let result = cz_manga_create(url.path, 1) else { throw failure("モデルを読み込めません: \(name)") }
            return result
        }
        if generator == nil { generator = try model("generator512") }

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
            guard shape == [1, 3, 512, 512] else { throw failure("生成画像の形式が不正です") }
            // 既定の基準色が中立。各RGBの比率で全画素を同じように補正する。
            // 顔・胴体・手足・背景を区別せず、黒い線は持ち上げない。
            let neutral: [Float] = [0.96, 0.76, 0.65]
            for c in 0..<3 {
                let gain = 1 + (skin[c] / neutral[c] - 1) * skinStrength
                for p in 0..<area { result[c*area+p] *= gain }
            }
            NSLog("[Manga] 全体色補正 seconds=%.3f", Date().timeIntervalSince(start))
            return bytes(result) as NSData
        } catch {
            os_log("[Manga] 着色失敗: %{public}@", type: .error, error.localizedDescription)
            return nil
        }
    }

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

}
