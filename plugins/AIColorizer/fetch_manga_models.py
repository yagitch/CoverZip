"""固定リビジョンの研究用モデルを取得し、全ファイルのハッシュを検証する。"""
import hashlib
import json
import pathlib
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = "https://huggingface.co/VioletXF/manga-character-parts-coreml/resolve/d607441ba4d3d14da84494eadc1a99da727c42f9/"
destination = pathlib.Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
manifest = json.load(urllib.request.urlopen(ROOT + "manifest.json"))

def fetch(entry):
    target = destination / entry["path"]
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
        temporary = target.with_name(target.name + ".download")
        urllib.request.urlretrieve(ROOT + entry["path"], temporary)
        assert temporary.stat().st_size == entry["bytes"]
        assert hashlib.sha256(temporary.read_bytes()).hexdigest() == entry["sha256"]
        temporary.replace(target)
    print("検証済み:", entry["path"], flush=True)

with ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(fetch, [item for item in manifest["files"] if item["path"] != "foreground.onnx"]))
for name in ["SOURCES.md", "README.md", "notices/foreground-LICENSE.txt", "notices/parser-architecture-LICENSE.txt", "notices/generator-model-card.md", "notices/head-model-card.md"]:
    target = destination / name
    target.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(ROOT + name, target)
