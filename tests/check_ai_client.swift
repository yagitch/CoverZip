import AppKit

enum CZAppGroup { static let identifier = "6KCX8JYZB7.com.yagitch.CoverZip" }
final class CZSettings {
    static let shared = CZSettings()
    var autoColorizeColorImages = false
}

@main struct CheckAIClient {
    static func main() {
        let context = CGContext(data: nil, width: 8192, height: 4096, bitsPerComponent: 8, bytesPerRow: 8192 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8192, height: 4096))
        let source = context.makeImage()!, slot = NSObject(), client = AIColorizerClient()
        var complete = false
        client.render(source, slot: slot) { _ in fatalError("古いページの結果が適用されました") }
        client.cancelAll()
        let start = Date()
        client.render(source, slot: slot) { output in
            precondition(output.width == 2048 && output.height == 1024)
            print("8192x4096 -> プラグイン指定サイズで推論 -> \(output.width)x\(output.height)合成、初回全体ms=\(Date().timeIntervalSince(start)*1000)")
            complete = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(complete, "着色結果が返りませんでした")
        complete = false
        let warmStart = Date()
        client.render(source, slot: slot) { output in
            precondition(output.width == 2048 && output.height == 1024)
            print("読み込み後の縮小・推論・合成ms=\(Date().timeIntervalSince(warmStart)*1000)")
            complete = true
        }
        while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(complete)
        print("高解像度画像の縮小・非同期合成・取り消しを確認")
    }
}
