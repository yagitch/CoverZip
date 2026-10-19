import Foundation

// 本体と同じチーム・App Groupで署名して使用するローカル導入ツール。
let manager = FileManager.default
guard CommandLine.arguments.count == 2,
      let root = manager.containerURL(forSecurityApplicationGroupIdentifier: "6KCX8JYZB7.com.yagitch.CoverZip") else {
    fatalError("署名・App Group・プラグインのパスを確認してください")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bundle = Bundle(url: source), bundle.bundleIdentifier == "com.yagitch.CoverZip.AIColorizer" else {
    fatalError("対象プラグインではありません")
}
let directory = root.appendingPathComponent("Library/Application Support/CoverZip/PlugIns")
try manager.createDirectory(at: directory, withIntermediateDirectories: true)
let destination = directory.appendingPathComponent("AIColorizer.bundle")
if manager.fileExists(atPath: destination.path) {
    let backup = directory.appendingPathComponent("AIColorizer-\(Int(Date().timeIntervalSince1970)).backup")
    try manager.moveItem(at: destination, to: backup)
}
try manager.copyItem(at: source, to: destination)
print("プラグイン導入先: \(destination.path)")
