"""実際のファイルオープン用ログへ、書式記号を含むパスを渡す回帰テスト。"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "CoverZip/AppDelegate.swift").read_text()
logs = [line.strip() for line in source.splitlines()
        if "NSLog(" in line and "application:open" in line]
assert len(logs) == 4
harness = r'''
import Foundation
let filename = "/Volumes/共有/紙2/テスト %s %@ %n 100%.zip"
let filenames = [filename]
let urls = [URL(fileURLWithPath: filename)]
''' + "\n".join(logs)
with tempfile.TemporaryDirectory(prefix="coverzip-logging-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(harness)
    result = subprocess.run(["xcrun", "swift", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "テスト %s %@ %n 100%.zip" in result.stderr, result.stderr
    assert "%E5%85%B1" in result.stderr, result.stderr

# 外部入力を含むログを、再び書式文字列に戻さない。
for name in ["CoverZip/AppDelegate.swift", "CoverZip/Services/KeywordMatcher.swift",
             "CoverZip/Services/SettingsFileManager.swift", "Shared/ZipCore.swift"]:
    for line in (root / name).read_text().splitlines():
        if 'NSLog(' in line and '\\(' in line:
            assert 'NSLog("%@", ' in line, (name, line)
print("日本語URL・%書式記号を含む4種類のオープン用ログ: OK")
