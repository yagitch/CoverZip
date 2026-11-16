import AppKit

enum CZAppGroup { static let identifier = "6KCX8JYZB7.com.yagitch.CoverZip" }
enum CZAIPlugin { static let relativePath = "Library/Application Support/CoverZip/PlugIns/AIColorizer.bundle" }
final class CZSettings {
    static let shared = CZSettings()
    var autoColorizeColorImages = false
    var aiColorizeModel = "manga"
    var mangaColorStrength = 0.55
    var mangaSkinRGB = [0.96, 0.76, 0.65]
    var mangaSkinStrength = 0.45
}

@main struct CheckAIClient {
    static func main() {
        let context = CGContext(data: nil, width: 8192, height: 4096, bitsPerComponent: 8, bytesPerRow: 8192 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8192, height: 4096))
        let source = context.makeImage()!, slot = NSObject(), client = AIColorizerClient()
        var complete = false
        client.render(source, slot: slot, status: { _ in fatalError("古いページの状態が通知されました") }) { _ in
            fatalError("古いページの結果が適用されました")
        }
        client.cancelAll()
        let start = Date()
        CZSettings.shared.mangaColorStrength = 0
        var pale: Data?
        client.render(source, slot: slot) { output in
            precondition(output.width == 2048 && output.height == 1024)
            pale = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
            print("8192x4096 -> プラグイン指定サイズで推論 -> \(output.width)x\(output.height)合成、初回全体ms=\(Date().timeIntervalSince(start)*1000)")
            complete = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(complete, "着色結果が返りませんでした")
        complete = false
        CZSettings.shared.mangaColorStrength = 1
        let warmStart = Date()
        client.render(source, slot: slot) { output in
            precondition(output.width == 2048 && output.height == 1024)
            precondition(pale != NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]), "色の濃さが反映されていません")
            print("読み込み後の縮小・推論・合成ms=\(Date().timeIntervalSince(warmStart)*1000)")
            complete = true
        }
        while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(complete)
        complete = false
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8192, height: 4096))
        client.render(context.makeImage()!, slot: slot, status: { text in
            if text.contains("除外") { complete = true }
        }) { _ in fatalError("カラー画像が除外されませんでした") }
        let colorDeadline = Date().addingTimeInterval(10)
        while !complete && Date() < colorDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(complete, "除外の状態が返りませんでした")
        print("高解像度画像の縮小・非同期合成・取り消し・カラー除外の状態通知を確認")
    }
}
