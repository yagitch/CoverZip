#!/bin/bash
set -euo pipefail
# モデルは別途取得し、公開リポジトリへは含めない。
model_dir="${1:?モデルのディレクトリ}"
output_dir="${2:?出力ディレクトリ}"
source_dir="$(cd "$(dirname "$0")" && pwd)"
# 評価したモデルと同一であることを確認し、上流の差し替えを自動採用しない。
printf '%s  %s\n' \
  db81f0d5e5b38d1ef6c877ae468e459d2f72193e8b905b0125e1d4a8a43135ca "$model_dir/colorizer_core.mlmodel" \
  3c910f143b76880ce3e865b504ffa25582c9c801201989484f3750454d88caee "$model_dir/colorizer_tail.mlmodel" | shasum -a 256 -c -
bundle="$output_dir/AIColorizer.bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun swiftc -O -emit-library -module-name AIColorizer "$source_dir/AIColorizer.swift" -o "$bundle/Contents/MacOS/AIColorizer"
for model in colorizer_core colorizer_tail; do
    xcrun coremlcompiler compile "$model_dir/$model.mlmodel" "$bundle/Contents/Resources"
done
cp "$source_dir/Info.plist" "$bundle/Contents/Info.plist"
codesign --force --sign 'Apple Development' --options runtime "$bundle"
codesign --verify --strict "$bundle"
