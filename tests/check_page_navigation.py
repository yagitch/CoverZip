"""Xcode不要のページ境界回帰テスト。実装のメソッドを抽出してSwiftで実行する。

画像デコードやQuick Lookの統合動作は対象外。ビルド後に実機確認する。
"""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "coverZipViewer/ImageManager.swift").read_text()


def method(name):
    start = source.index("    func " + name + "(")
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
    init(_ count: Int) { imageEntryCount = count }
""" + method("nextImage") + "\n" + method("previousImage") + """
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
"""

with tempfile.TemporaryDirectory(prefix="coverzip-paging-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(harness)
    subprocess.run(["swift", str(path)], check=True)
