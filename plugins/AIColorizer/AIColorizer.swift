import Foundation
import CoreML
import CoreVideo

/// 独立バンドルの入口。入出力は常に256×256 BGRA、原寸画像は受け取らない。
@objc(CZAIColorizerPlugin)
public final class AIColorizerPlugin: NSObject {
    private var core: MLModel?
    private var tail: MLModel?

    @objc public func colorizeBGRA(_ input: NSData) -> NSData? {
        guard input.length == 256 * 256 * 4 else { return nil }
        do {
            if core == nil || tail == nil {
                let bundle = Bundle(for: Self.self)
                let config = MLModelConfiguration()
                config.computeUnits = .all
                guard let coreURL = bundle.url(forResource: "colorizer_core", withExtension: "mlmodelc"),
                      let tailURL = bundle.url(forResource: "colorizer_tail", withExtension: "mlmodelc") else { return nil }
                core = try MLModel(contentsOf: coreURL, configuration: config)
                tail = try MLModel(contentsOf: tailURL, configuration: config)
            }
            let original = try buffer(input as Data)
            let prediction = try core!.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image_small": MLFeatureValue(pixelBuffer: original)]))
            guard let colors = prediction.featureValue(for: "colorized_small_image")?.multiArrayValue,
                  let encoded = pixels(colors) else { return nil }
            let ab = try buffer(encoded)
            let result = try tail!.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: original), "ab": MLFeatureValue(pixelBuffer: ab)
            ]))
            guard let output = result.featureValue(for: "colorized_image")?.multiArrayValue else { return nil }
            return pixels(output) as NSData?
        } catch {
            NSLog("[AIColorizer] 着色に失敗: %@", error.localizedDescription)
            return nil
        }
    }

    private func buffer(_ data: Data) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 256, 256, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result) == kCVReturnSuccess,
              let result else { throw NSError(domain: "AIColorizer", code: 1) }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        data.withUnsafeBytes { bytes in
            for row in 0..<256 {
                memcpy(CVPixelBufferGetBaseAddress(result)! + row * CVPixelBufferGetBytesPerRow(result), bytes.baseAddress! + row * 1024, 1024)
            }
        }
        return result
    }

    private func pixels(_ values: MLMultiArray) -> Data? {
        let shape = values.shape.map(\.intValue)
        guard shape.count >= 3, Array(shape.suffix(3)) == [3, 256, 256] else { return nil }
        let strides = values.strides.map(\.intValue)
        let channelStride = strides[strides.count - 3]
        let rowStride = strides[strides.count - 2], colStride = strides[strides.count - 1]
        guard values.dataType == .float32 else { return nil }
        let floats = values.dataPointer.assumingMemoryBound(to: Float.self)
        var result = Data(count: 256 * 256 * 4)
        result.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<256 { for x in 0..<256 {
                let dest = (y * 256 + x) * 4
                for channel in 0..<3 {
                    let value = floats[channel * channelStride + y * rowStride + x * colStride]
                    bytes[dest + 2 - channel] = UInt8(value.isFinite ? max(0, min(255, value)) : 0)
                }
                bytes[dest + 3] = 255
            }}
        }
        return result
    }
}
