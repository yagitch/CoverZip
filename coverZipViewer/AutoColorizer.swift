import AppKit

/// 白黒の階調を配色へ置き換える表示用エフェクト。原本・デコードキャッシュは変更しない。
final class AutoColorizer {
    private final class Entry: NSObject {
        let source: CGImage
        let result: CGImage
        init(_ source: CGImage, _ result: CGImage) { self.source = source; self.result = result }
    }
    private let cache = NSCache<NSString, Entry>()
    private var signature = ""

    func image(_ image: NSImage?) -> NSImage? {
        guard let image, CZSettings.shared.autoColorizeEnabled,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        return NSImage(cgImage: apply(cg), size: image.size)
    }

    func apply(_ source: CGImage) -> CGImage {
        let settings = CZSettings.shared
        guard settings.autoColorizeEnabled else { return source }
        let palette = settings.autoColorizePalette
        let nextSignature = "\(settings.autoColorizeColorImages):\(palette)"
        if nextSignature != signature { cache.removeAllObjects(); signature = nextSignature }
        cache.totalCostLimit = 64 * 1024 * 1024
        let key = String(describing: Unmanaged.passUnretained(source).toOpaque()) as NSString
        if let entry = cache.object(forKey: key) { return entry.result }
        let width = source.width, height = source.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return source }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        if !settings.autoColorizeColorImages {
            // JPEGの微小な色ずれは許容し、色付きページはそのまま表示する。
            var colored = 0, samples = 0
            for pixel in stride(from: 0, to: width * height, by: max(1, width * height / 16384)) {
                let i = pixel * 4
                guard bytes[i + 3] > 32 else { continue }
                samples += 1
                if Int(max(bytes[i], bytes[i + 1], bytes[i + 2])) - Int(min(bytes[i], bytes[i + 1], bytes[i + 2])) > 12 { colored += 1 }
            }
            if colored > max(2, samples / 1000) {
                cache.setObject(Entry(source, source), forKey: key, cost: width * height * 4)
                return source
            }
        }
        let colors: [[Double]] = [[0, 0, 0]] + palette + [[1, 1, 1]]
        // EdgeView2の階調テストを参考にした独自の補間。黒と白を保持する。
        let stops = [0.0, 0.5, 0.65, 0.78, 0.9, 1.0]
        let table: [[UInt8]] = (0...255).map { value in
            let level = Double(value) / 255
            let upper = min(stops.firstIndex(where: { $0 >= level }) ?? 5, 5)
            let lower = max(0, upper - 1)
            let t = upper == lower ? 0 : (level - stops[lower]) / (stops[upper] - stops[lower])
            return (0..<3).map { channel in UInt8(max(0, min(255, ((colors[lower][channel] * (1 - t) + colors[upper][channel] * t) * 255).rounded()))) }
        }
        for pixel in 0..<(width * height) {
            let i = pixel * 4, alpha = Double(bytes[i + 3]) / 255
            guard alpha > 0 else { continue }
            let gray = min(255, Int(((0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])) / alpha).rounded()))
            for channel in 0..<3 { bytes[i + channel] = UInt8((Double(table[gray][channel]) * alpha).rounded()) }
        }
        guard let result = context.makeImage() else { return source }
        cache.setObject(Entry(source, result), forKey: key, cost: width * height * 8)
        return result
    }
}
