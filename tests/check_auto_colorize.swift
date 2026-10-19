import AppKit

// 描画処理を実物で検証し、永続設定への書込みだけを置き換える。
final class CZSettings {
    static let shared = CZSettings()
    var autoColorizeEnabled = false
    var autoColorizeColorImages = false
    var autoColorizePalette = [[0.098, 0.238, 0.418], [0.695, 0.258, 0.434], [0.883, 0.5, 0.449], [0.965, 0.781, 0.609]]
}

@main struct ColorizeTests {
    static func image(_ values: [UInt8]) -> CGImage {
        let data = Data(values) as CFData
        return CGImage(width: values.count / 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: values.count, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    static func pixels(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: 1, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: 1))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * 4))
    }
    static func main() {
        let effect = AutoColorizer(), settings = CZSettings.shared
        let gray = image([0,0,0,255, 128,128,128,255, 255,255,255,255, 0,0,0,0])
        assert(effect.apply(gray) === gray)
        settings.autoColorizeEnabled = true
        let output = pixels(effect.apply(gray))
        assert(Array(output[0..<4]) == [0,0,0,255])
        assert(output[4] < output[5] && output[5] < output[6])
        assert(Array(output[8..<12]) == [255,255,255,255])
        assert(output[15] == 0)
        let color = image(Array(repeating: [255,0,0,255], count: 16).flatMap { $0 })
        assert(effect.apply(color) === color)
        settings.autoColorizeColorImages = true
        assert(pixels(effect.apply(color)) != pixels(color))
        settings.autoColorizePalette = Array(repeating: [0.0,1.0,0.0], count: 4)
        let changed = pixels(effect.apply(gray))
        assert(changed[5] > 240 && changed[4] < 5 && changed[6] < 5)
        settings.autoColorizeEnabled = false
        assert(effect.apply(gray) === gray)
        print("自動着色: 無効時、黒白保持、着色、透過、カラー除外、強制適用、配色変更の検証に成功")
    }
}
