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

    static func shiftedArrowCommand(for event: NSEvent) -> CZPreviewSessionCommand? {
        guard event.type == .keyDown, event.modifierFlags.contains(.shift),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: return .jumpLeftArrowPages
        case 124: return .jumpRightArrowPages
        default: return nil
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let shiftedArrow = Self.shiftedArrowCommand(for: event)
        if let command = Self.overviewCommand(for: event) ?? shiftedArrow {
            // 長押しや下位のメニュー／Responderで一覧が再度切り替わることを防ぐ。
            if !event.isARepeat || shiftedArrow != nil { PreviewSessionCommandDispatcher.post(command: command) }
            return
        }
        super.sendEvent(event)
    }
}
