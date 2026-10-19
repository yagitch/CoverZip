//
//  AppSettings.swift
//  CoverZip (App target)
//
//  SwiftUI 向けに統一設定を公開する ObservableObject ラッパー
//

import Foundation
import Combine

/// SwiftUI用の設定ラッパー
/// CZSettingsを基に@Published プロパティを提供し、SwiftUIの自動更新に対応
final class AppSettingsWriter: ObservableObject {
    static let shared = AppSettingsWriter()

    private let core = CZSettings.shared
    private var isLoadingSettings = false
    @Published var autoColorizeEnabled = false {
        didSet {
            core.autoColorizeEnabled = autoColorizeEnabled
            if autoColorizeEnabled && aiColorizeEnabled {
                aiColorizeEnabled = false
            } else { notifyColorizeChange() }
        }
    }
    @Published var aiColorizeEnabled = false {
        didSet {
            core.aiColorizeEnabled = aiColorizeEnabled
            if aiColorizeEnabled && autoColorizeEnabled {
                autoColorizeEnabled = false
            } else { notifyColorizeChange() }
        }
    }
    @Published var autoColorizeColorImages = false {
        didSet { core.autoColorizeColorImages = autoColorizeColorImages; notifyColorizeChange() }
    }
    @Published var autoColorizePalette = CZSettings.defaultColorizePalette {
        didSet { core.autoColorizePalette = autoColorizePalette; notifyColorizeChange() }
    }
    private func notifyColorizeChange() {
        guard !isLoadingSettings else { return }
        DistributedNotificationCenter.default().postNotificationName(CZDistributedNotifications.settingsChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @Published var isRightToLeftReading: Bool = true {
        didSet {
            core.isRightToLeftReading = isRightToLeftReading
            if !isLoadingSettings {
                PreviewSessionCommandDispatcher.postReadingDirectionChanged(isRightToLeft: isRightToLeftReading)
            }
        }
    }

    @Published var sliderVisibilityWidthThreshold: Double = 600.0 {
        didSet { core.sliderVisibilityWidthThreshold = sliderVisibilityWidthThreshold }
    }

    @Published var alwaysSinglePageForCover: Bool = true {
        didSet { core.alwaysSinglePageForCover = alwaysSinglePageForCover }
    }

    @Published var defaultViewMode: ViewModePreference = .auto {
        didSet { core.defaultViewMode = defaultViewMode }
    }

    @Published var slideshowInterval: Double = 3.0 {
        didSet { core.slideshowInterval = slideshowInterval }
    }

    @Published var isThumbnailStripVisible: Bool = true {
        didSet {
            core.isThumbnailStripVisible = isThumbnailStripVisible
            notifySettingsChangedIfNeeded()
        }
    }

    @Published var quitOnLastViewerKeyboardClose: Bool = true {
        didSet { core.quitOnLastViewerKeyboardClose = quitOnLastViewerKeyboardClose }
    }
    @Published var pageLoopEnabled: Bool = true {
        didSet { core.pageLoopEnabled = pageLoopEnabled }
    }
    @Published var viewerPageStatusHideDelay: Int = 3 {
        didSet {
            core.viewerPageStatusHideDelay = viewerPageStatusHideDelay
            NotificationCenter.default.post(name: CZDistributedNotifications.settingsChanged, object: nil)
        }
    }
    @Published var showViewerPageStatus: Bool = true {
        didSet {
            core.showViewerPageStatus = showViewerPageStatus
            NotificationCenter.default.post(name: CZDistributedNotifications.settingsChanged, object: nil)
        }
    }

    @Published var restoreWindowFrameEnabled: Bool = true {
        didSet { core.restoreWindowFrameEnabled = restoreWindowFrameEnabled }
    }

    @Published var imageDecodeCachePolicy: CZImageDecodeCachePolicy = .deferred {
        didSet { core.imageDecodeCachePolicy = imageDecodeCachePolicy }
    }

    @Published var pageTransitionEnabled: Bool = true {
        didSet {
            core.pageTransitionEnabled = pageTransitionEnabled
            notifySettingsChangedIfNeeded()
        }
    }

    @Published var isKeyHelperEnabled: Bool = false {
        didSet { core.isKeyHelperEnabled = isKeyHelperEnabled }
    }

    private init() {
        // コア設定から現在値を読み込む
        loadSettings()
    }

    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        isRightToLeftReading = core.isRightToLeftReading
        sliderVisibilityWidthThreshold = core.sliderVisibilityWidthThreshold
        alwaysSinglePageForCover = core.alwaysSinglePageForCover
        slideshowInterval = core.slideshowInterval
        isThumbnailStripVisible = core.isThumbnailStripVisible
        restoreWindowFrameEnabled = core.restoreWindowFrameEnabled
        quitOnLastViewerKeyboardClose = core.quitOnLastViewerKeyboardClose
        pageLoopEnabled = core.pageLoopEnabled
        showViewerPageStatus = core.showViewerPageStatus
        viewerPageStatusHideDelay = core.viewerPageStatusHideDelay
        autoColorizeEnabled = core.autoColorizeEnabled
        aiColorizeEnabled = core.aiColorizeEnabled
        autoColorizeColorImages = core.autoColorizeColorImages
        autoColorizePalette = core.autoColorizePalette
        imageDecodeCachePolicy = core.imageDecodeCachePolicy
        pageTransitionEnabled = core.pageTransitionEnabled
        defaultViewMode = core.defaultViewMode
        isKeyHelperEnabled = core.isKeyHelperEnabled
    }

    private func notifySettingsChangedIfNeeded() {
        if !isLoadingSettings {
            PreviewSessionCommandDispatcher.postSettingsChanged()
        }
    }

    var savedWindowFrameString: String? {
        get { core.savedWindowFrameString }
        set { core.savedWindowFrameString = newValue }
    }
}
