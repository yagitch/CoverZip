import AppKit

@main struct CheckAIPlugin {
    static func main() {
        guard CommandLine.arguments.count == 2,
              let bundle = Bundle(path: CommandLine.arguments[1]),
              let type = bundle.principalClass as? NSObject.Type else { fatalError("プラグインを読み込めません") }
        let plugin = type.init(), selector = NSSelectorFromString("colorizeBGRA:")
        precondition(plugin.responds(to: selector))
        precondition(plugin.perform(selector, with: Data(count: 4) as NSData)?.takeUnretainedValue() == nil)
        var input = Data(count: 256 * 256 * 4)
        for y in 0..<256 { for x in 0..<256 {
            let index = (y * 256 + x) * 4
            let gray = UInt8((x / 32 + y / 32) % 2 == 0 ? 190 : 70)
            for channel in 0..<3 { input[index + channel] = gray }
            input[index + 3] = 255
        }}
        for run in 0..<4 {
            let start = Date()
            guard let result = plugin.perform(selector, with: input as NSData)?.takeUnretainedValue() as? Data else { fatalError("推論失敗") }
            precondition(result.count == input.count)
            precondition(stride(from: 3, to: result.count, by: 4).allSatisfy { result[$0] == 255 })
            precondition(result != input)
            print("run=\(run) pipeline_ms=\(Date().timeIntervalSince(start) * 1000)")
        }
        print("AIプラグイン: 不正サイズの拒否・推論・出力サイズ・透明度を確認")
    }
}
