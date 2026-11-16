import Foundation

enum AIPluginInstaller {
    static func verify(_ url: URL) throws {
        guard Bundle(url: url)?.bundleIdentifier == "com.yagitch.CoverZip.AIColorizer" else {
            throw NSError(domain: "CoverZipInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: "対象プラグインではありません"])
        }
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        check.arguments = ["--verify", "--deep", "--strict", "--all-architectures", url.path]
        try check.run()
        check.waitUntilExit()
        let details = Process(), pipe = Pipe()
        details.executableURL = check.executableURL
        details.arguments = ["-dv", url.path]
        details.standardError = pipe
        try details.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        details.waitUntilExit()
        let team = CZAppGroup.identifier.split(separator: ".").first.map(String.init) ?? ""
        guard check.terminationStatus == 0, details.terminationStatus == 0,
              String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).contains("TeamIdentifier=\(team)") else {
            throw NSError(domain: "CoverZipInstall", code: 2, userInfo: [NSLocalizedDescriptionKey: "署名または署名チームが一致しません"])
        }
    }

    /// 同じディレクトリで準備・検証を済ませ、旧版のバックアップを残して置換する。
    static func install(source: URL, directory: URL, validate: (URL) throws -> Void = verify) throws -> URL {
        let manager = FileManager.default
        try validate(source)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("AIColorizer.bundle")
        let staged = directory.appendingPathComponent(".AIColorizer-\(UUID().uuidString).bundle")
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: source, to: staged)
        try validate(staged)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staged,
                backupItemName: "AIColorizer-\(UUID().uuidString).backup", options: .withoutDeletingBackupItem)
        } else {
            try manager.moveItem(at: staged, to: destination)
        }
        return destination
    }
}

#if !INSTALLER_TEST
@main struct InstallAIPlugin {
    static func main() throws {
        guard CommandLine.arguments.count == 2,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CZAppGroup.identifier) else {
            throw NSError(domain: "CoverZipInstall", code: 3, userInfo: [NSLocalizedDescriptionKey: "署名・App Group・プラグインのパスを確認してください"])
        }
        let destination = try AIPluginInstaller.install(
            source: URL(fileURLWithPath: CommandLine.arguments[1]),
            directory: root.appendingPathComponent(CZAIPlugin.relativePath).deletingLastPathComponent())
        print("プラグイン導入先: \(destination.path)")
    }
}
#endif
