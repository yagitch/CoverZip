//
//  WindowSettingsView.swift
//  CoverZip
//
//  Created by Codex on 2026/03/13.
//

import SwiftUI

struct WindowSettingsView: View {
    @ObservedObject private var settings = AppSettingsWriter.shared

    var body: some View {
        Form {
            Section {
                Toggle("最後の閲覧ウインドウをキーで閉じたらアプリを終了", isOn: $settings.quitOnLastViewerKeyboardClose)
            } footer: {
                Text("本体でバッククオート・バックスラッシュ（Command＋W）を使ったときに適用します。他のウインドウが開いている場合やFinderのQuick Lookには適用しません。")
            }
            Section {
                Toggle(CZLocalized.string("settings.window.restore_frame", defaultValue: "Restore window size and position"), isOn: Binding(
                    get: { settings.restoreWindowFrameEnabled },
                    set: { settings.restoreWindowFrameEnabled = $0 }
                ))

                if settings.savedWindowFrameString != nil {
                    Button(CZLocalized.string("settings.window.reset_saved_frame", defaultValue: "Reset saved window frame"), role: .destructive) {
                        settings.savedWindowFrameString = nil
                    }
                }
            } header: {
                Label(CZLocalized.string("settings.window.section", defaultValue: "Window"), systemImage: "macwindow")
            } footer: {
                Text(
                    CZLocalized.string(
                        "settings.window.footer",
                        defaultValue: "When enabled, the next preview opens with the previous window size and position."
                    )
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    WindowSettingsView()
}
