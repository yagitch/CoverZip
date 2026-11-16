"""Xcode不要のページ境界回帰テスト。実装のメソッドを抽出してSwiftで実行する。

画像デコードやQuick Lookの統合動作は対象外。ビルド後に実機確認する。
"""
from pathlib import Path
import subprocess
import tempfile
import re

source = (Path(__file__).resolve().parents[1] / "coverZipViewer/ImageManager.swift").read_text()


def method(name):
    start = re.search(r"    (?:private )?func " + re.escape(name) + r"\(", source).start()
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


harness = """
final class CZSettings {
    static let shared = CZSettings()
    var pageLoopEnabled = true
}
final class Paging {
    var imageEntryCount: Int
    var currentIndex: Int = 0
    var spreadPairOffset = 0
    init(_ count: Int) { imageEntryCount = count }
""" + '\n'.join(method(name) for name in ['nextImage', 'previousImage', 'shiftSpreadOnePage', 'getCurrentSpreadPairIndices', 'resolveSpreadPairIndices']) + """
}

func check(_ count: Int, _ spread: Bool, _ expected: [Int]) {
    let paging = Paging(count)
    for index in expected {
        precondition(paging.nextImage(isSpreadMode: spread))
        precondition(paging.currentIndex == index)
    }
}
check(5, false, [1, 2, 3, 4, 0, 1])
check(4, false, [1, 2, 3, 0, 1])
check(5, true, [1, 3, 0, 1])
check(4, true, [1, 3, 0, 1])
check(2, true, [1, 0, 1])

for count in 0...1 {
    for spread in [false, true] {
        let paging = Paging(count)
        precondition(!paging.nextImage(isSpreadMode: spread))
        precondition(paging.currentIndex == 0)
        precondition(!paging.previousImage(isSpreadMode: spread))
    }
}
// 任意ページへのジャンプ後も、範囲外に進まず先頭へ戻る。
for count in 2...8 {
    for spread in [false, true] {
        let paging = Paging(count)
        paging.currentIndex = count - 1
        precondition(paging.nextImage(isSpreadMode: spread))
        precondition(paging.currentIndex == 0)
        precondition(paging.previousImage(isSpreadMode: spread))
        precondition(paging.currentIndex == (spread ? ((count - 2) / 2) * 2 + 1 : count - 1))
        precondition(paging.nextImage(isSpreadMode: spread))
        precondition(paging.currentIndex == 0)
        precondition(!paging.previousImage(isSpreadMode: spread, wrapsAtStart: false))
        paging.currentIndex = count - 1
        precondition(!paging.nextImage(isSpreadMode: spread, wrapsAtEnd: false))
        precondition(paging.currentIndex == count - 1)
    }
}
let previous = Paging(5)
previous.currentIndex = 3
precondition(previous.previousImage(isSpreadMode: true) && previous.currentIndex == 1)
precondition(previous.previousImage(isSpreadMode: true) && previous.currentIndex == 0)
CZSettings.shared.pageLoopEnabled = false
for count in 2...8 {
    for spread in [false, true] {
        let paging = Paging(count)
        precondition(!paging.previousImage(isSpreadMode: spread))
        precondition(paging.currentIndex == 0)
        paging.currentIndex = count - 1
        precondition(!paging.nextImage(isSpreadMode: spread))
        precondition(paging.currentIndex == count - 1)
        precondition(paging.previousImage(isSpreadMode: spread))
    }
}
print("ページ送り回帰テスト: 成功")

func pair(_ paging: Paging, _ rtl: Bool) -> [Int] {
    let indices = paging.getCurrentSpreadPairIndices(isRightToLeft: rtl)
    return [indices.left, indices.right].compactMap { $0 }.sorted()
}
for rtl in [false, true] {
    let paging = Paging(8)
    paging.currentIndex = 1
    precondition(pair(paging, rtl) == [1, 2])
    precondition(paging.shiftSpreadOnePage(forward: true))
    precondition(pair(paging, rtl) == [2, 3])
    precondition(paging.nextImage(isSpreadMode: true))
    precondition(pair(paging, rtl) == [4, 5])
    precondition(paging.shiftSpreadOnePage(forward: false))
    precondition(pair(paging, rtl) == [3, 4])
    precondition(paging.shiftSpreadOnePage(forward: false))
    precondition(pair(paging, rtl) == [2, 3])
    // ペアの後半ページを基準に開いた場合も、表示中のペアから1ページだけ動く。
    paging.currentIndex = 2
    paging.spreadPairOffset = 0
    precondition(paging.shiftSpreadOnePage(forward: true))
    precondition(pair(paging, rtl) == [2, 3])
    paging.currentIndex = 1
    paging.spreadPairOffset = 0
    precondition(paging.shiftSpreadOnePage(forward: false))
    precondition(pair(paging, rtl) == [0])
    precondition(!paging.shiftSpreadOnePage(forward: false))
    paging.currentIndex = 6
    paging.spreadPairOffset = 1
    precondition(pair(paging, rtl) == [6, 7])
    precondition(paging.shiftSpreadOnePage(forward: true))
    precondition(pair(paging, rtl) == [7])
    precondition(!paging.shiftSpreadOnePage(forward: true))
}
for count in 0...1 {
    let paging = Paging(count)
    precondition(!paging.shiftSpreadOnePage(forward: true))
    precondition(!paging.shiftSpreadOnePage(forward: false))
}
print("見開き1ページ移動テスト: 両綴じ方向・連続移動・先頭末尾に成功")
"""

with tempfile.TemporaryDirectory(prefix="coverzip-paging-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(harness)
    subprocess.run(["swift", str(path)], check=True)
