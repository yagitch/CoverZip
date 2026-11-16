import AppKit

/// 閲覧中のフォーカスや日本語入力の状態に依存せず、一覧の操作を受け取る。
final class ViewerWindow: NSWindow {
    static func overviewCommand(for event: NSEvent) -> CZPreviewSessionCommand? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 5: return .togglePageOverview
        case 53: return .dismissPageOverview
        default: return nil
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if let command = Self.overviewCommand(for: event) {
            // 長押しや下位のメニュー／Responderで一覧が再度切り替わることを防ぐ。
            if !event.isARepeat { PreviewSessionCommandDispatcher.post(command: command) }
            return
        }
        super.sendEvent(event)
    }
}
