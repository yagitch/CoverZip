"""本体の細いページ位置バーが、サムネイル非表示時に再表示されないことを検証する。"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'CoverZip/Services/QLPreviewInputDriver.swift').read_text()
start = source.index('        private func showTemporarily()')
end = source.index('\n    private final class ViewerProgressBar:', start)
method = source[start:end].rsplit('\n    }', 1)[0].replace('private func', 'func', 1)
harness = r'''
import AppKit
final class CZSettings {
    static let shared = CZSettings()
    var showViewerPageStatus = true
    var viewerPageStatusHideDelay = 3
}
final class Indicator {
    var hideWork: DispatchWorkItem?
    let bar = NSView()
    var total = 24
    var isThumbnailStripVisible = false
    var isPageOverviewVisible = false
''' + method + r'''
}
let indicator = Indicator()
indicator.showTemporarily()
precondition(indicator.bar.isHidden)
indicator.isThumbnailStripVisible = true
indicator.showTemporarily()
precondition(!indicator.bar.isHidden)
indicator.isThumbnailStripVisible = false
for _ in 0..<5 { indicator.showTemporarily() }
precondition(indicator.bar.isHidden)
indicator.isThumbnailStripVisible = true
indicator.isPageOverviewVisible = true
indicator.showTemporarily()
precondition(indicator.bar.isHidden)
indicator.isPageOverviewVisible = false
indicator.showTemporarily()
precondition(!indicator.bar.isHidden)
CZSettings.shared.showViewerPageStatus = false
indicator.showTemporarily()
precondition(indicator.bar.isHidden)
indicator.hideWork?.cancel()
print("本体ページ位置バーテスト: 非表示直後・繰り返し操作・ページ一覧中の抑制に成功")
'''
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='coverzip-indicator-') as tmp:
    directory = Path(tmp)
    (directory / 'main.swift').write_text(harness)
    binary = directory / 'check'
    subprocess.run(['xcrun', 'swiftc', str(directory / 'main.swift'), '-o', str(binary)], env=env, check=True)
    subprocess.run([str(binary)], env=env, check=True)
