import AppKit
import CoreImage
import os.log

/// プラグイン未導入時は原画を維持する。AIモデルと推論コードは本体へリンクしない。
final class AIColorizerClient {
    private static let queue = DispatchQueue(label: "com.yagitch.CoverZip.ai-color", qos: .userInitiated)
    private static var plugin: NSObject?
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private var requests: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var generations: [ObjectIdentifier: UUID] = [:]

    func cancelAll() {
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        generations.removeAll()
    }

    func cancel(slot: AnyObject) {
        let key = ObjectIdentifier(slot)
        requests.removeValue(forKey: key)?.cancel()
        generations.removeValue(forKey: key)
    }

    func render(_ source: CGImage, slot: AnyObject, completion: @escaping (CGImage) -> Void) {
        cancel(slot: slot)
        let key = ObjectIdentifier(slot), generation = UUID()
        generations[key] = generation
        let includeColor = CZSettings.shared.autoColorizeColorImages
        let operation = DispatchWorkItem { [weak self] in
            // 待機中にページが変わった処理は、モデルを呼ぶ前に除外する。
            let valid = DispatchQueue.main.sync { self?.generations[key] == generation }
            guard valid else { return }
            let result = autoreleasepool { Self.process(source, includeColor: includeColor) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generations[key] == generation else { return }
                self.requests.removeValue(forKey: key)
                self.generations.removeValue(forKey: key)
                if let result { completion(result) }
            }
        }
        requests[key] = operation
        Self.queue.async(execute: operation)
    }

    private static func process(_ source: CGImage, includeColor: Bool) -> CGImage? {
        // AI境界の手前で固定サイズへ縮小。巨大な原寸画像はプラグインへ渡さない。
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                space: space, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let bytes = small.data else { return nil }
        small.interpolationQuality = .medium
        small.setFillColor(CGColor(gray: 1, alpha: 1))
        small.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        small.draw(source, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        if !includeColor {
            let pixels = bytes.assumingMemoryBound(to: UInt8.self)
            var colored = 0
            for i in stride(from: 0, to: 256 * 256 * 4, by: 16) {
                if Int(max(pixels[i], pixels[i+1], pixels[i+2])) - Int(min(pixels[i], pixels[i+1], pixels[i+2])) > 12 { colored += 1 }
            }
            if colored > 16 { return nil }
        }
        if plugin == nil {
            guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CZAppGroup.identifier),
                  let bundle = Bundle(url: root.appendingPathComponent("Library/Application Support/CoverZip/PlugIns/AIColorizer.bundle")),
                  let type = bundle.principalClass as? NSObject.Type else { return nil }
            plugin = type.init()
            os_log("AIColorizer plugin loaded (256x256)", type: .info)
        }
        let selector = NSSelectorFromString("colorizeBGRA:")
        guard let plugin, plugin.responds(to: selector),
              let result = plugin.perform(selector, with: Data(bytes: bytes, count: 256 * 256 * 4) as NSData)?.takeUnretainedValue() as? Data,
              result.count == 256 * 256 * 4,
              let provider = CGDataProvider(data: result as CFData),
              let colors = CGImage(width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        // 表示合成も長辺2048以内。色だけを拡大し、線画の明暗は元画像から取得する。
        let scale = min(1, 2048 / CGFloat(max(source.width, source.height)))
        let base = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let color = CIImage(cgImage: colors).transformed(by: CGAffineTransform(scaleX: base.extent.width / 256, y: base.extent.height / 256))
        let merged = color.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        let masked = merged.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: base])
        return context.createCGImage(masked, from: base.extent)
    }
}
