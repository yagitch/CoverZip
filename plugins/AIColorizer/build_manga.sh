#!/bin/bash
set -euo pipefail
model_dir="${1:?モデルのディレクトリ}"
runtime_dir="${2:?ONNX Runtimeのディレクトリ}"
output_dir="${3:?出力ディレクトリ}"
fast_model_dir="${4:?高速モデルのディレクトリ}"
source_dir="$(cd "$(dirname "$0")" && pwd)"
bundle="$output_dir/AIColorizer.bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
xcrun clang++ -std=c++17 -O2 -fPIC -I "$runtime_dir/include" -c "$source_dir/MangaRuntime.cpp" -o "$output_dir/MangaRuntime.o"
xcrun swiftc -O -D MANGA_BUNDLE -emit-library -module-name MangaColorizer -import-objc-header "$source_dir/MangaRuntime.h" \
  "$source_dir/MangaColorizer.swift" "$source_dir/AIColorizer.swift" "$output_dir/MangaRuntime.o" -lc++ -L "$runtime_dir/lib" -lonnxruntime \
  -Xlinker -rpath -Xlinker @loader_path/../Frameworks -o "$bundle/Contents/MacOS/AIColorizer"
cp "$runtime_dir/lib/libonnxruntime.1.31.0.dylib" "$bundle/Contents/Frameworks/"
ln -sf libonnxruntime.1.31.0.dylib "$bundle/Contents/Frameworks/libonnxruntime.1.dylib"
cp "$runtime_dir/LICENSE" "$bundle/Contents/Resources/ONNXRuntime-LICENSE.txt"
cp "$runtime_dir/ThirdPartyNotices.txt" "$bundle/Contents/Resources/ONNXRuntime-ThirdPartyNotices.txt"
for name in head.onnx foreground-fp16.onnx generator512.onnx; do cp "$model_dir/$name" "$bundle/Contents/Resources/"; done
xcrun coremlcompiler compile "$model_dir/Parts.mlpackage" "$bundle/Contents/Resources"
cp -R "$model_dir/notices" "$bundle/Contents/Resources/"
cp "$model_dir/SOURCES.md" "$bundle/Contents/Resources/"
for model in colorizer_core colorizer_tail; do
  xcrun coremlcompiler compile "$fast_model_dir/$model.mlmodel" "$bundle/Contents/Resources"
done
cp "$source_dir/Info.plist" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$bundle/Contents/Info.plist"
codesign --force --sign 'Apple Development' --options runtime "$bundle/Contents/Frameworks/libonnxruntime.1.31.0.dylib"
codesign --force --sign 'Apple Development' --options runtime "$bundle"
codesign --verify --deep --strict "$bundle"
