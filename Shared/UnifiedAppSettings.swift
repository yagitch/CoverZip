//
//  UnifiedAppSettings.swift
//  CoverZip Shared
//
//  全ターゲットで共有する統一設定アクセスレイヤー
//

import Foundation

/// 共有設定アクセスレイヤー
/// App Group経由でUserDefaultsにアクセスし、全ターゲットで一貫した設定管理を提供
public final class CZSettings {

    // MARK: - 共有インスタンス
    public static let shared = CZSettings()

    private let defaults: UserDefaults

    private convenience init() {
        self.init(defaults: UserDefaults(suiteName: CZAppGroup.identifier) ?? .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        registerDefaults()
        // 旧版で両方オンの場合は、従来実際に使われていたAI側を維持する。
        if defaults.bool(forKey: CZSettingsKeys.aiColorizeEnabled) {
            defaults.set(false, forKey: CZSettingsKeys.autoColorizeEnabled)
        }
    }

    // MARK: - 既定値登録
    private func registerDefaults() {
        defaults.register(defaults: [
            CZSettingsKeys.isRightToLeftReading: true,
            CZSettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            CZSettingsKeys.alwaysSinglePageForCover: true,
            CZSettingsKeys.defaultViewMode: "auto",
            CZSettingsKeys.slideshowInterval: 3.0,
            CZSettingsKeys.slideshowEnabled: false,
            CZSettingsKeys.thumbnailStripVisible: true,
            CZSettingsKeys.pageTransitionEnabled: true,
            CZSettingsKeys.restoreWindowFrameEnabled: true,
            CZSettingsKeys.readingHistoryEnabled: true,
            CZSettingsKeys.isKeyHelperEnabled: false,
            CZSettingsKeys.spreadPairOffset: 0,
            CZSettingsKeys.imageDecodeCachePolicy: CZImageDecodeCachePolicy.deferred.rawValue
        ])
    }

    // MARK: - UserDefaults 直接アクセス
    public var userDefaults: UserDefaults {
        return defaults
    }

    // MARK: - 読み方向
    public static let defaultColorizePalette = [[0.098, 0.238, 0.418], [0.695, 0.258, 0.434], [0.883, 0.5, 0.449], [0.965, 0.781, 0.609]]
    public var autoColorizeEnabled: Bool {
        get { defaults.bool(forKey: CZSettingsKeys.autoColorizeEnabled) && !aiColorizeEnabled }
        set {
            if newValue { defaults.set(false, forKey: CZSettingsKeys.aiColorizeEnabled) }
            defaults.set(newValue, forKey: CZSettingsKeys.autoColorizeEnabled)
        }
    }
    public var aiColorizeEnabled: Bool {
        get { defaults.bool(forKey: CZSettingsKeys.aiColorizeEnabled) }
        set {
            if newValue { defaults.set(false, forKey: CZSettingsKeys.autoColorizeEnabled) }
            defaults.set(newValue, forKey: CZSettingsKeys.aiColorizeEnabled)
        }
    }
    public var autoColorizeColorImages: Bool {
        get { defaults.bool(forKey: CZSettingsKeys.autoColorizeColorImages) }
        set { defaults.set(newValue, forKey: CZSettingsKeys.autoColorizeColorImages) }
    }
    public var aiColorizeModel: String {
        get { defaults.string(forKey: CZSettingsKeys.aiColorizeModel) == "fast" ? "fast" : "manga" }
        set { defaults.set(newValue == "fast" ? "fast" : "manga", forKey: CZSettingsKeys.aiColorizeModel) }
    }
    public var mangaColorStrength: Double {
        get {
            guard let value = defaults.object(forKey: CZSettingsKeys.mangaColorStrength) as? Double, value.isFinite else { return 0.55 }
            return min(1, max(0, value))
        }
        set { defaults.set(newValue.isFinite ? min(1, max(0, newValue)) : 0.55, forKey: CZSettingsKeys.mangaColorStrength) }
    }
    public var autoColorizePalette: [[Double]] {
        get {
            guard let colors = defaults.array(forKey: CZSettingsKeys.autoColorizePalette) as? [[Double]],
                  colors.count == 4, colors.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { return Self.defaultColorizePalette }
            return colors
        }
        set { defaults.set(newValue, forKey: CZSettingsKeys.autoColorizePalette) }
    }
    public static let defaultSkinRGB: [Double] = [0.96, 0.76, 0.65]
    public var mangaSkinRGB: [Double] {
        get {
            guard let value = defaults.array(forKey: CZSettingsKeys.mangaSkinRGB) as? [Double],
                  value.count == 3, value.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return Self.defaultSkinRGB }
            return value
        }
        set { defaults.set(newValue, forKey: CZSettingsKeys.mangaSkinRGB) }
    }
    public var mangaSkinStrength: Double {
        get {
            guard let value = defaults.object(forKey: CZSettingsKeys.mangaSkinStrength) as? Double, value.isFinite else { return 0.45 }
            return min(1, max(0, value))
        }
        set { defaults.set(newValue.isFinite ? min(1, max(0, newValue)) : 0.45, forKey: CZSettingsKeys.mangaSkinStrength) }
    }
    public var isRightToLeftReading: Bool {
        get { defaults.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.isRightToLeftReading) }
    }

    // MARK: - UI しきい値
    public var sliderVisibilityWidthThreshold: Double {
        get { defaults.object(forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) }
    }

    // MARK: - 表紙ページ処理
    public var alwaysSinglePageForCover: Bool {
        get { defaults.object(forKey: CZSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.alwaysSinglePageForCover) }
    }

    // MARK: - 表示モード
    public var defaultViewMode: ViewModePreference {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto"
            return ViewModePreference(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.defaultViewMode) }
    }

    // MARK: - スライドショー
    public var slideshowInterval: Double {
        get { defaults.object(forKey: CZSettingsKeys.slideshowInterval) as? Double ?? 3.0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.slideshowInterval) }
    }

    public var isSlideshowEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.slideshowEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: CZSettingsKeys.slideshowEnabled) }
    }

    public var isThumbnailStripVisible: Bool {
        get { defaults.object(forKey: CZSettingsKeys.thumbnailStripVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.thumbnailStripVisible) }
    }

    // MARK: - ウィンドウフレーム永続化
    public var pageLoopEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.pageLoopEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.pageLoopEnabled) }
    }
    public var showViewerPageStatus: Bool {
        get { defaults.object(forKey: CZSettingsKeys.showViewerPageStatus) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.showViewerPageStatus) }
    }
    public var viewerPageStatusHideDelay: Int {
        get { max(1, defaults.object(forKey: CZSettingsKeys.viewerPageStatusHideDelay) as? Int ?? 3) }
        set { defaults.set(max(1, newValue), forKey: CZSettingsKeys.viewerPageStatusHideDelay) }
    }

    public var quitOnLastViewerKeyboardClose: Bool {
        get { defaults.object(forKey: CZSettingsKeys.quitOnLastViewerKeyboardClose) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.quitOnLastViewerKeyboardClose) }
    }

    public var restoreWindowFrameEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.restoreWindowFrameEnabled) }
    }

    public var savedWindowFrameString: String? {
        get { defaults.string(forKey: CZSettingsKeys.savedWindowFrameString) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: CZSettingsKeys.savedWindowFrameString)
            } else {
                defaults.removeObject(forKey: CZSettingsKeys.savedWindowFrameString)
            }
        }
    }

    // MARK: - 読書履歴
    public var readingHistoryEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.readingHistoryEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.readingHistoryEnabled) }
    }

    // MARK: - Finder QuickLook キー入力ヘルパー
    public var isKeyHelperEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.isKeyHelperEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: CZSettingsKeys.isKeyHelperEnabled) }
    }

    // MARK: - 画像デコードキャッシュ方針
    public var imageDecodeCachePolicy: CZImageDecodeCachePolicy {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.imageDecodeCachePolicy) ?? CZImageDecodeCachePolicy.deferred.rawValue
            return CZImageDecodeCachePolicy(rawValue: raw) ?? .deferred
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.imageDecodeCachePolicy) }
    }

    // MARK: - 見開きペア補正
    public var spreadPairOffset: Int {
        get { defaults.object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.spreadPairOffset) }
    }

    // MARK: - ページ遷移
    public var pageTransitionEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.pageTransitionEnabled) }
    }
}
