#!/bin/bash
set -euo pipefail
model_dir="${1:?モデルのディレクトリ}"
runtime_dir="${2:?ONNX Runtimeのディレクトリ}"
output_dir="${3:?出力ディレクトリ}"
fast_model_dir="${4:?高速モデルのディレクトリ}"
source_dir="$(cd "$(dirname "$0")" && pwd)"
source "$source_dir/build_environment.sh"
printf '%s  %s\n' \
  24e409aa2a5aa4bd89f622717634d759a28649a663c1ef90871f893df593a227 "$model_dir/generator512.onnx" \
  2a50a63e7f41f8d4d551d3ee47248df3864f6540109fce8ad520ca3b51af4b70 "$runtime_dir/lib/libonnxruntime.1.31.0.dylib" \
  db81f0d5e5b38d1ef6c877ae468e459d2f72193e8b905b0125e1d4a8a43135ca "$fast_model_dir/colorizer_core.mlmodel" \
  3c910f143b76880ce3e865b504ffa25582c9c801201989484f3750454d88caee "$fast_model_dir/colorizer_tail.mlmodel" | shasum -a 256 -c -
bundle="$output_dir/AIColorizer.bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
xcrun clang++ -arch arm64 -mmacosx-version-min=14.0 -std=c++17 -O2 -fPIC -I "$runtime_dir/include" -c "$source_dir/MangaRuntime.cpp" -o "$output_dir/MangaRuntime.o"
xcrun swiftc -target arm64-apple-macos14.0 -O -D MANGA_BUNDLE -emit-library -module-name MangaColorizer -import-objc-header "$source_dir/MangaRuntime.h" \
  "$source_dir/MangaColorizer.swift" "$source_dir/AIColorizer.swift" "$output_dir/MangaRuntime.o" -lc++ -L "$runtime_dir/lib" -lonnxruntime \
  -Xlinker -rpath -Xlinker @loader_path/../Frameworks -o "$bundle/Contents/MacOS/AIColorizer"
cp "$runtime_dir/lib/libonnxruntime.1.31.0.dylib" "$bundle/Contents/Frameworks/"
ln -sf libonnxruntime.1.31.0.dylib "$bundle/Contents/Frameworks/libonnxruntime.1.dylib"
cp "$runtime_dir/LICENSE" "$bundle/Contents/Resources/ONNXRuntime-LICENSE.txt"
cp "$runtime_dir/ThirdPartyNotices.txt" "$bundle/Contents/Resources/ONNXRuntime-ThirdPartyNotices.txt"
cp "$model_dir/generator512.onnx" "$bundle/Contents/Resources/"
cp -R "$model_dir/notices" "$bundle/Contents/Resources/"
cp "$model_dir/SOURCES.md" "$bundle/Contents/Resources/"
for model in colorizer_core colorizer_tail; do
  xcrun coremlcompiler compile "$fast_model_dir/$model.mlmodel" "$bundle/Contents/Resources"
done
cp "$source_dir/Info.plist" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 5' "$bundle/Contents/Info.plist"
shasum -a 256 "$model_dir/generator512.onnx" "$fast_model_dir/"*.mlmodel "$runtime_dir/lib/libonnxruntime.1.31.0.dylib" > "$bundle/Contents/Resources/build-inputs.sha256"
codesign --force --sign "$COVERZIP_SIGN_IDENTITY" --options runtime "$bundle/Contents/Frameworks/libonnxruntime.1.31.0.dylib"
codesign --force --sign "$COVERZIP_SIGN_IDENTITY" --options runtime "$bundle"
verify_plugin_team "$bundle"
