import Foundation

@main struct CheckColorizeSettings {
    static func main() {
        let suite = "CoverZip.ColorizeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // 旧版の同時オン設定を再現する。
        defaults.set(true, forKey: CZSettingsKeys.autoColorizeEnabled)
        defaults.set(true, forKey: CZSettingsKeys.aiColorizeEnabled)
        let settings = CZSettings(defaults: defaults)
        precondition(settings.aiColorizeEnabled && !settings.autoColorizeEnabled)
        precondition(!defaults.bool(forKey: CZSettingsKeys.autoColorizeEnabled))
        settings.autoColorizeEnabled = true
        precondition(settings.autoColorizeEnabled && !settings.aiColorizeEnabled)
        precondition(!defaults.bool(forKey: CZSettingsKeys.aiColorizeEnabled))
        settings.aiColorizeEnabled = true
        precondition(settings.aiColorizeEnabled && !settings.autoColorizeEnabled)
        settings.aiColorizeEnabled = false
        precondition(!settings.autoColorizeEnabled && !settings.aiColorizeEnabled)
        settings.autoColorizeEnabled = true
        let reopened = CZSettings(defaults: defaults)
        precondition(reopened.autoColorizeEnabled && !reopened.aiColorizeEnabled)
        print("着色設定: 旧設定の移行・双方向排他・両方オフ・再読込を確認")
    }
}
