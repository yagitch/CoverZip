"""本体の一覧ショートカットを、フォーカス・入力文字・長押しを変えて検証する。"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = r'''
import AppKit

enum PreviewSessionCommandDispatcher {
    static var commands: [CZPreviewSessionCommand] = []
    static func post(command: CZPreviewSessionCommand) { commands.append(command) }
}
final class FocusedView: NSView {
    var receivedKeys = 0
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { receivedKeys += 1 }
}
func key(_ code: UInt16, _ text: String, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false, type: NSEvent.EventType = .keyDown) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
        isARepeat: repeatKey, keyCode: code)!
}
let app = NSApplication.shared
let window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
let focus = FocusedView()
window.contentView = focus
precondition(window.makeFirstResponder(focus))
for text in ["g", "G", "き"] {
    window.sendEvent(key(5, text))
}
precondition(PreviewSessionCommandDispatcher.commands == [.togglePageOverview, .togglePageOverview, .togglePageOverview])
precondition(focus.receivedKeys == 0)
window.sendEvent(key(53, "\u{1b}"))
precondition(PreviewSessionCommandDispatcher.commands.last == .dismissPageOverview)
let count = PreviewSessionCommandDispatcher.commands.count
window.sendEvent(key(5, "g", repeatKey: true))
precondition(PreviewSessionCommandDispatcher.commands.count == count)
for flag: NSEvent.ModifierFlags in [.command, .control, .option] {
    precondition(ViewerWindow.overviewCommand(for: key(5, "g", flags: flag)) == nil)
}
precondition(ViewerWindow.overviewCommand(for: key(5, "g", type: .keyUp)) == nil)
precondition(ViewerWindow.overviewCommand(for: key(123, "")) == nil)
print("本体キー入力テスト: フォーカス移動・日本語入力・Esc・長押し・修飾キーに成功")
'''
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='coverzip-viewer-keys-') as tmp:
    directory = Path(tmp)
    (directory / 'main.swift').write_text(harness)
    binary = directory / 'check'
    subprocess.run(['xcrun', 'swiftc', str(root / 'Shared/SettingsKeys.swift'),
                    str(root / 'CoverZip/Services/ViewerWindow.swift'), str(directory / 'main.swift'),
                    '-o', str(binary)], check=True, env=env)
    subprocess.run([str(binary)], check=True, env=env)
