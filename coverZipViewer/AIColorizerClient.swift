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

    func render(_ source: CGImage, slot: AnyObject, includeColorOverride: Bool? = nil,
                status: @escaping (String) -> Void = { _ in }, completion: @escaping (CGImage) -> Void) {
        cancel(slot: slot)
        let key = ObjectIdentifier(slot), generation = UUID()
        generations[key] = generation
        let includeColor = includeColorOverride ?? CZSettings.shared.autoColorizeColorImages
        let model = CZSettings.shared.aiColorizeModel
        let strength = CZSettings.shared.mangaColorStrength
        let skin = CZSettings.shared.mangaSkinRGB + [CZSettings.shared.mangaSkinStrength]
        let operation = DispatchWorkItem { [weak self] in
            // 待機中にページが変わった処理は、モデルを呼ぶ前に除外する。
            let valid = DispatchQueue.main.sync { self?.generations[key] == generation }
            guard valid else { return }
            DispatchQueue.main.async { [weak self] in
                guard self?.generations[key] == generation else { return }
                status("AI着色：準備・処理中（\(model == "fast" ? "高速" : "漫画用")）")
            }
            let result: (CGImage?, String) = autoreleasepool {
                do {
                    return try Self.process(source, includeColor: includeColor, model: model, strength: strength, skin: skin)
                } catch {
                    NSLog("[AIColorizer] %@", error.localizedDescription)
                    return (nil, "AI着色：\(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generations[key] == generation else { return }
                self.requests.removeValue(forKey: key)
                self.generations.removeValue(forKey: key)
                status(result.1)
                if let image = result.0 { completion(image) }
            }
        }
        requests[key] = operation
        Self.queue.async(execute: operation)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CoverZipAI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func process(_ source: CGImage, includeColor: Bool, model: String, strength: Double, skin: [Double]) throws -> (CGImage?, String) {
        if plugin == nil {
            guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CZAppGroup.identifier) else {
                throw failure("共有フォルダへアクセスできません。署名とApp Groupを確認してください。")
            }
            let url = root.appendingPathComponent(CZAIPlugin.relativePath)
            guard FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) else {
                throw failure("プラグインがありません。設定画面のフォルダを確認してください。")
            }
            do { try bundle.loadAndReturnError() }
            catch { throw failure("プラグインを読み込めません：\(error.localizedDescription)") }
            guard let type = bundle.principalClass as? NSObject.Type else { throw failure("プラグインの入口が不正です。") }
            plugin = type.init()
        }
        guard let plugin else { throw failure("プラグインを初期化できません。") }
        let modelSelector = NSSelectorFromString("selectModel:")
        if plugin.responds(to: modelSelector) { plugin.perform(modelSelector, with: model as NSString) }
        let skinSelector = NSSelectorFromString("configureSkin:")
        if plugin.responds(to: skinSelector) { plugin.perform(skinSelector, with: skin as NSArray) }
        let sizeSelector = NSSelectorFromString("inputSideLength")
        let side = plugin.responds(to: sizeSelector)
            ? (plugin.perform(sizeSelector)?.takeUnretainedValue() as? NSNumber)?.intValue ?? 256 : 256
        guard side == 256 || side == 512 else { throw failure("プラグインの入力サイズに対応していません。") }
        // AI境界の手前で固定サイズへ縮小。巨大な原寸画像はプラグインへ渡さない。
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let bytes = small.data else { throw failure("縮小画像を作成できません。") }
        small.interpolationQuality = .medium
        small.setFillColor(CGColor(gray: 1, alpha: 1))
        small.fill(CGRect(x: 0, y: 0, width: side, height: side))
        small.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        if !includeColor {
            let pixels = bytes.assumingMemoryBound(to: UInt8.self)
            var colored = 0
            for i in stride(from: 0, to: side * side * 4, by: 16) {
                if Int(max(pixels[i], pixels[i+1], pixels[i+2])) - Int(min(pixels[i], pixels[i+1], pixels[i+2])) > 12 { colored += 1 }
            }
            if colored > side * side / 4096 { return (nil, "AI着色：カラー画像のため除外（設定で変更できます）") }
        }
        let selector = NSSelectorFromString("colorizeBGRA:")
        guard plugin.responds(to: selector) else { throw failure("プラグインの着色メソッドがありません。") }
        guard let result = plugin.perform(selector, with: Data(bytes: bytes, count: side * side * 4) as NSData)?.takeUnretainedValue() as? Data else {
            throw failure("モデルの推論に失敗しました。モデルと実行ログを確認してください。")
        }
        guard result.count == side * side * 4,
              let provider = CGDataProvider(data: result as CFData),
              let colors = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw failure("プラグインの出力形式が不正です。") }
        // 表示合成も長辺2048以内。色だけを拡大し、線画の明暗は元画像から取得する。
        let scale = min(1, 2048 / CGFloat(max(source.width, source.height)))
        let base = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let color = CIImage(cgImage: colors).transformed(by: CGAffineTransform(scaleX: base.extent.width / CGFloat(side), y: base.extent.height / CGFloat(side)))
        var merged = color.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        if model == "manga" && side == 512 && strength > 0 {
            // 原画が白でも色を残し、黒い線は乗算で維持する。0は従来の合成。
            let tinted = color.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: base])
            merged = merged.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: tinted, kCIInputTimeKey: strength])
        }
        let masked = merged.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: base])
        guard let image = context.createCGImage(masked, from: base.extent) else { throw failure("着色画像を合成できません。") }
        return (image, "AI着色：完了（\(model == "fast" ? "高速" : "漫画用")）")
    }
}
