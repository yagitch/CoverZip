import Foundation

@main struct CheckAIInstall {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("coverzip-install-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source.bundle")
        let directory = root.appendingPathComponent("installed")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: source.appendingPathComponent("version"))
        let destination = try AIPluginInstaller.install(source: source, directory: directory, validate: { _ in })
        try Data("new".utf8).write(to: source.appendingPathComponent("version"))
        var validationCount = 0
        do {
            _ = try AIPluginInstaller.install(source: source, directory: directory, validate: { _ in
                validationCount += 1
                if validationCount == 2 { throw NSError(domain: "test", code: 1) }
            })
            fatalError("検証失敗を無視しました")
        } catch { }
        let retained = try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8)
        precondition(retained == "old")
        _ = try AIPluginInstaller.install(source: source, directory: directory, validate: { _ in })
        let replaced = try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8)
        precondition(replaced == "new")
        let backup = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "backup" }!
        let previous = try String(contentsOf: backup.appendingPathComponent("version"), encoding: .utf8)
        precondition(previous == "old")
        print("導入前検証の失敗で旧版維持・正常置換・旧版バックアップを確認")
    }
}
