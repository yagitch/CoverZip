import AppKit

@main struct CheckMangaPlugin {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let bundle = Bundle(path: args[1]),
              let type = bundle.principalClass as? NSObject.Type,
              let source = NSImage(contentsOfFile: args[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("入力を読み込めません") }
        let plugin = type.init(), selector = NSSelectorFromString("colorizeBGRA:")
        let side = (plugin.perform(NSSelectorFromString("inputSideLength"))?.takeUnretainedValue() as! NSNumber).intValue
        precondition(side == 512)
        precondition(plugin.perform(selector, with: Data(count: 4) as NSData)?.takeUnretainedValue() == nil)
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side*4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        let input = Data(bytes: context.data!, count: side*side*4)
        var baseline: Data?
        for run in 0..<2 {
            let start = Date()
            guard let result = plugin.perform(selector, with: input as NSData)?.takeUnretainedValue() as? Data else { fatalError("推論失敗") }
            precondition(result.count == input.count && result != input)
            baseline = result
            precondition(stride(from: 3, to: result.count, by: 4).allSatisfy { result[$0] == 255 })
            result.withUnsafeBytes { context.data!.copyMemory(from: $0.baseAddress!, byteCount: result.count) }
            try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
            print("run=\(run) seconds=\(Date().timeIntervalSince(start))")
        }
        let skinSelector = NSSelectorFromString("configureSkin:")
        plugin.perform(skinSelector, with: [0.4, 0.6, 0.95, 0.8] as NSArray)
        let changed = plugin.perform(selector, with: input as NSData)?.takeUnretainedValue() as? Data
        precondition(changed != nil && changed != baseline, "肌色パラメータが反映されていません")
        print("肌色RGB・補正量の出力変化を確認")
        let selection = NSSelectorFromString("selectModel:")
        plugin.perform(selection, with: "fast" as NSString)
        precondition((plugin.perform(NSSelectorFromString("inputSideLength"))?.takeUnretainedValue() as! NSNumber).intValue == 256)
        let fastInput = Data(repeating: 180, count: 256*256*4)
        precondition((plugin.perform(selector, with: fastInput as NSData)?.takeUnretainedValue() as? Data)?.count == fastInput.count)
        plugin.perform(selection, with: "manga" as NSString)
        precondition((plugin.perform(NSSelectorFromString("inputSideLength"))?.takeUnretainedValue() as! NSNumber).intValue == 512)
        print("高速→漫画モデルの切替を確認")
    }
}
