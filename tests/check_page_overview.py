"""実際の一覧ビューをコンパイルし、配置・単クリック・Esc・読込中断を検証する。"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manager = (root / "coverZipViewer/ImageManager.swift").read_text()
protocol = manager[manager.index("protocol ThumbnailImageProviding"):manager.index("/**")]
helper = (root / "CoverZipKeyHelper/KeyHelperController.swift").read_text()
start = helper.index("    private func commandForKeyEvent(")
end = helper.index("    private func postCommand(", start)
routing_method = helper[start:end].replace("private func", "func", 1)
harness = r'''
import AppKit

final class Provider: ThumbnailImageProviding {
    var pending: [(Int, () -> Bool, (Int, NSImage?) -> Void)] = []
    var requested: [Int] = []
    func cachedTinyImage(at index: Int) -> NSImage? { nil }
    func requestTinyImage(at index: Int, maxPixelSize: Int, isStillNeeded: @escaping () -> Bool, completion: @escaping (Int, NSImage?) -> Void) {
        precondition(maxPixelSize <= 256)
        requested.append(index)
        pending.append((index, isStillNeeded, completion))
    }
    func finish() {
        let batch = pending
        pending.removeAll()
        batch.forEach { $0.2($0.0, NSImage(size: NSSize(width: 16, height: 24))) }
    }
}

func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}
func settle(_ window: NSWindow) {
    window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
let overview = PageOverviewView(frame: NSRect(x: 0, y: 0, width: 750, height: 600))
overview.autoresizingMask = [.width, .height]
window.contentView = overview
let provider = Provider()
overview.thumbnailProvider = provider
var activated: [Int] = []
var dismissCount = 0
overview.onPageActivated = { activated.append($0) }
overview.onDismiss = { dismissCount += 1 }
overview.show(itemCount: 300, currentIndex: 90, isRightToLeft: false)
settle(window)
let collection = descendants(overview).compactMap { $0 as? NSCollectionView }.first!
precondition(collection.numberOfItems(inSection: 0) == 300)
precondition(collection.selectionIndexPaths == [IndexPath(item: 90, section: 0)])
precondition(collection.indexPathsForVisibleItems().contains(IndexPath(item: 90, section: 0)))
precondition(provider.requested.count > 0 && provider.pending.count <= 2)
let layout = collection.collectionViewLayout!
let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
let second = layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
precondition(first.minX < second.minX)
precondition(layout.collectionViewContentSize.height > overview.bounds.height)

// 選択済みページを単クリックしても、正確に1回だけ移動を要求する。
let selectedFrame = layout.layoutAttributesForItem(at: IndexPath(item: 90, section: 0))!.frame
let point = collection.convert(NSPoint(x: selectedFrame.midX, y: selectedFrame.midY), to: nil)
let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
collection.mouseDown(with: click)
precondition(activated == [90])
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
collection.keyDown(with: escape)
precondition(dismissCount == 1 && activated == [90])

// 閉じると進行中の読込を中断し、古い画像を次の一覧へ流さない。
overview.reset()
precondition(overview.isHidden && provider.pending.allSatisfy { !$0.1() })
overview.show(itemCount: 7, currentIndex: 0, isRightToLeft: true)
provider.finish()
settle(window)
precondition(collection.numberOfItems(inSection: 0) == 7)
let rtlFirst = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
let rtlSecond = layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
precondition(rtlFirst.minX > rtlSecond.minX)
precondition(provider.pending.count <= 2)
for _ in 0..<20 { provider.finish(); settle(window) }
precondition(provider.pending.isEmpty)
overview.reset()
overview.show(itemCount: 1, currentIndex: 0, isRightToLeft: false)
settle(window)
precondition(collection.numberOfItems(inSection: 0) == 1)
precondition(collection.selectionIndexPaths == [IndexPath(item: 0, section: 0)])
overview.reset()
provider.finish()
print("ページ一覧テスト: 配置・単クリック・Esc・世代切替・同時読込上限に成功")
'''
harness += "\nfinal class Routing {\nvar isPageOverviewVisible = false\n" + routing_method + r'''
}
let routing = Routing()
let escapeCG = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
escapeCG.flags = []
precondition(routing.commandForKeyEvent(escapeCG) == nil)
routing.isPageOverviewVisible = true
precondition(routing.commandForKeyEvent(escapeCG)?.command == .dismissPageOverview)
routing.isPageOverviewVisible = false
precondition(routing.commandForKeyEvent(escapeCG) == nil)
let gKey = CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: true)!
gKey.flags = []
precondition(routing.commandForKeyEvent(gKey)?.command == .togglePageOverview)
gKey.flags = .maskCommand
precondition(routing.commandForKeyEvent(gKey) == nil)
print("Finderキー転送テスト: G・一覧中のEsc・通常時のEsc通過に成功")
'''

env = dict(os.environ)
env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
with tempfile.TemporaryDirectory(prefix="coverzip-overview-") as directory:
    directory = Path(directory)
    (directory / "Protocol.swift").write_text("import AppKit\n" + protocol)
    (directory / "main.swift").write_text(harness)
    executable = directory / "check"
    subprocess.run(["xcrun", "swiftc", str(root / "Shared/SettingsKeys.swift"),
                    str(root / "coverZipViewer/PageOverviewView.swift"),
                    str(directory / "Protocol.swift"), str(directory / "main.swift"),
                    "-o", str(executable)], env=env, check=True)
    subprocess.run([str(executable)], env=env, check=True)
