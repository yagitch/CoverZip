# AI自動着色プラグイン

**現在の仕様（ビルド48／プラグインv5）**: 顔限定の補正を廃止し、漫画用generatorの出力全体へ
同じRGB係数をかける。顔・胴体・手足・服・背景を区別しない。HUDの「色合い補正」で強さを変更する。
係数は `1 + (指定RGB / 既定RGB - 1) × 強さ`。既定RGBが中立、強さ0でも無補正。
頭部・パーツ・前景のモデルは使用せず、新規バンドルへも含めない。高速モデルは従来どおり。
`configureSkin:` と設定キーは既存ホストとの互換性のため名前を保持するが、作用は画像全体である。
16区画すべてで変化すること、0%で中立出力へ戻ること、実機での反映を検証した。
このMacの最新版バンドルは `.local-backup/20261019/manga-plugin48/AIColorizer.bundle`。
以下のv4以前の顔検出・マスクの記述は変更履歴であり、現行の処理には適用しない。

ビルド47／プラグインv4: 「表示 → 色合い調整HUD…」で浮動パネルを開く。
RGB・HSV・カラーホイールは同じ肌色設定を編集する。既定RGBは0.96/0.76/0.65。
HUDには肌色補正量（既定45%）、全体の濃さ（既定55%）、モデル選択もある。
設定変更を0.25秒まとめて通知し、モデル処理後に閲覧画像へ反映する。
`configureSkin:` にNSArrayの4個のNSNumber（R/G/B/補正量、各0〜1）を渡す。
プラグインがこの任意メソッドを持たない旧版では肌色の指定は反映されない。
補正量0では顔へのヒント・補正を行わない。身体全体の肌の抽出には対応していない。
前景モデルが頭部切り出し全体を背景とするケースでは、目と肌のパーツ分類が成立した顔の
中央楕円内だけに限定して補正する。黒い線は除外し、誤認識時は補正量を下げて使う。
公開サンプルで肌色パラメータ変更による実際の画素差をテストし、実機HUDでも色反映を確認。

CoverZip本体とは独立してビルド・導入する `AIColorizer.bundle`。
推論コード・Core MLモデルはアプリへ埋め込まず、App Group内の
`Library/Application Support/CoverZip/PlugIns/` に配置する。
メニューバー「表示 → AI自動着色（プラグイン）」で切り替える。
本体の通常の自動着色は残し、ビルド44から一方をオンにすると他方をオフにする。
両方オフも可能。旧設定で両方オンだった場合は、従来実際に使われていたAI側だけを維持する。
Finder Quick Lookではどちらも実行しない。

ビルド46・プラグインv3では高速／漫画用の両モデルを一つの独立バンドルに保持する。
「設定 → ビューア設定 → AIモデル」で再起動せず切り替えられる。選択は保存する。
漫画用の「漫画の色の濃さ」（初期値55%）は0%で従来方式、100%で原画と推論色の乗算。
白い肌が原画の明るさで白へ戻る現象を軽減するが、画像全体にも効く。
モデル自体が付けなかった肌色や、身体の領域検出を補う調整ではない。

## 処理と境界

- 本体のQLPreviewViewだけがURL fragment `coverzip-native-viewer` を渡す。
  拡張は印のないプレビューを無着色にする。同一ファイルを本体とFinderで同時に開いて検証済み。
- プラグインABIはObjective-Cの `CZAIColorizerPlugin.colorizeBGRA:`。
  入出力はNSDataのBGRA8。任意の `inputSideLength()` が返すNSNumberで一辺を指定する。
  ビルド45は256または512だけを許可し、メソッドがない旧プラグインは256を使用する。
  漫画版は512×512（1048576バイト）。異なるサイズは拒否する。
- 原画像は呼び出し側で縮小してから渡す。旧core/tailは256×256、漫画版は512×512。
  縦横比は推論時のみ正方形へ変換し、合成時に元へ戻す。
- 着色画像の色と原画の明暗をCore Imageで合成する。合成出力は長辺2048px以下。
  原画の透明度を維持し、AI中間画像の低解像度を文字・線画へ直接適用しない。
- カラー画像は通常除外する。「カラー画像も着色する」で含める。
- 非同期の直列処理。各表示枠の古い要求は無効化し、ページ変更・設定変更・閉じる操作後に
  古い色を適用しない。処理中は原画を表示する。画像結果はディスクへ保存しない。
- モデルは初回使用時だけロードし、その表示プロセス内で再利用する。外部通信・API料金なし。
- プラグイン未導入・読み込み失敗時は原画で閲覧可能。
  設定画面の「AIプラグインのフォルダを開く」から独立した実体を確認できる。

## モデルと権利情報

ビルド45の漫画版は下記「漫画用モデル群」を使用する。以下は切り戻し用の旧版。

[Vadbeg/colorization-coreml](https://github.com/Vadbeg/colorization-coreml) の
`weights/colorizer_core.mlmodel` と `weights/colorizer_tail.mlmodel` を使用。
元モデルは [richzhang/colorization](https://github.com/richzhang/colorization) のSIGGRAPH17。
変換プロジェクトはMIT表記だが、モデル内のlicense metadataは `AI Future`。
このリポジトリでは重み・生成バンドルを配布しない。再配布する場合は重みの条件を別途確認する。
ビルドスクリプトが評価済みの2ファイルのSHA-256を照合する。

## 再ビルド・導入

リポジトリ直下から実行。Xcodeと本体と同じチームのApple Development署名を使用する。
このMacではモデルを `.local-backup/20261019/colorization-research/` に保持している。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash plugins/AIColorizer/build.sh \
  .local-backup/20261019/colorization-research .local-backup/20261019/ai-plugin
xcrun swiftc plugins/AIColorizer/install.swift -o .local-backup/install-ai-plugin
codesign --force --sign 'Apple Development' \
  --entitlements CoverZip/CoverZip.entitlements .local-backup/install-ai-plugin
.local-backup/install-ai-plugin .local-backup/20261019/ai-plugin/AIColorizer.bundle
```

既存プラグインは日付付きbackupへ退避する。プラグイン更新時には本体とQuick Lookを閉じ、
残っている `coverZipViewer` / `coverZipFolderViewer` の表示プロセスも終了してから再度開く。
削除も本体の再ビルドは不要。閉じた状態でバンドルをこのフォルダから退避する。
同じABIのプラグイン更新には本体再ビルドは不要。本体の呼び出し仕様を変える場合は必要。

## 検証

`tests/check_ai_plugin.swift` は不正サイズ拒否・モデルの推論と出力を検証する。
`tests/check_ai_client.swift` は8192×4096入力の縮小、2048×1024への合成、古い要求の取り消しを検証する。
後者はApp Groupアクセスのため本体と同じentitlements/署名が必要。
合成グレー画像でのM5実測: 初回モデル読み込み約2秒、読み込み後のプラグイン処理約35〜36ms。
原画のデコード・画面更新はこの時間に含まない。漫画の着色品質は保証しない。
8192×4096の合成グレー画像では、読み込み後の縮小・推論・2048×1024への合成を含め約92ms。

## 肌への特化の調査（2026-10-19）

肌・髪の領域を扱う [Manga character parts pack](https://huggingface.co/VioletXF/manga-character-parts-coreml)
は単独の着色モデルではなく、512pxのパーツ解析、頭部検出、前景分離などを組み合わせる研究用構成。
配布者のApple Silicon測定では前景分離だけでFP16約215〜225msであり、このMacでの測定値ではない。
横顔・重なりなどの精度制限も明記されている。ビルド44時点では速度条件を優先して採用しなかった。
[ColorComic](https://github.com/vikast908/ColorComic)にも肌色補正はあるが、領域分割とCLIP等を組み合わせる方式。
「肌の着色に特化し、現在の速度条件も満たす」差し替えモデルは今回の調査では確認できず、ビルド44では重みを維持した。

## 漫画用モデル群（ビルド45）

利用者が速度低下を許容したため、上記パックの固定revision
`d607441ba4d3d14da84494eadc1a99da727c42f9` を採用した。
`generator512.onnx`、`head.onnx`、`Parts.mlpackage`、`foreground-fp16.onnx`を使う独自の簡略パイプライン。
配布元の人物同定・参照画像・色管理などの全機能を移植したものではない。

1. 縮小したページを漫画用generatorで着色する。
2. 640角の頭部検出で最大6頭部を選び、各切り出しを512角でパーツ分類する。
3. 肌と目の判定が十分な顔だけ、1024角の前景分離を適用する。
4. 肌の領域に疎な肌色ヒントを与えて再着色し、その領域だけ穏やかに補正する。

顔中心の推定であり、手足・全身の肌を特別に抽出する処理ではない。
固定の淡い肌色ヒントを使うため、正しい人物の色やコマ間の色の一致は保証しない。
文字・線画の明暗は従来どおり原画から合成する。入力画像・生成結果のディスク保存はしない。
モデルの実行準備で作られるOSのコンパイルキャッシュは、ページ画像のキャッシュとは別。

ONNX Runtime 1.31.0（公式macOS arm64配布）をバンドル内に配置する。
プレビュー拡張での実行を考慮しCore MLはCPU/GPUを使用し、ONNX Runtimeのテレメトリーは無効。
モデルの重み・ランタイム・生成バンドルはGitへ含めない。各モデルの出典・権利情報は
パックのSOURCES.mdとnoticesをバンドルへ同梱する。再配布条件は別途確認が必要。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 plugins/AIColorizer/fetch_manga_models.py .local-backup/20261019/manga-models
# 公式配布から取得・展開（このMacでは取得済み）
curl -fL https://github.com/microsoft/onnxruntime/releases/download/v1.31.0/onnxruntime-osx-arm64-1.31.0.tgz \
  -o .local-backup/20261019/manga-models/onnxruntime.tgz
echo '1031b36dd3bdaa8d976a6130d9cf2a05e9be320b93ae804f8427b91dc3432afc  .local-backup/20261019/manga-models/onnxruntime.tgz' | shasum -a 256 -c -
tar -xzf .local-backup/20261019/manga-models/onnxruntime.tgz -C .local-backup/20261019/manga-models
bash plugins/AIColorizer/build_manga.sh .local-backup/20261019/manga-models \
  .local-backup/20261019/manga-models/onnxruntime-osx-arm64-1.31.0 .local-backup/20261019/manga-plugin \
  .local-backup/20261019/colorization-research
# 上記の手順で署名済みinstall-ai-pluginを作成してから実行
.local-backup/install-ai-plugin .local-backup/20261019/manga-plugin/AIColorizer.bundle
```

本体とプレビューを閉じ、残存する表示プロセスも終了してから入れ替える。
通常の高速版への切替は設定画面で行う。プラグイン全体を旧高速版へ戻す場合だけ
`.local-backup/20261019/ai-plugin/AIColorizer.bundle` を同じ導入ツールへ渡す。
ビルド45は旧版の256角ABIにも対応するため、本体の切り戻しは不要。

検証: `tests/check_manga_plugin.swift` は公開の漫画サンプルを入力し、サイズ契約・着色・透明度を確認。
M5でCPU/GPU構成の初回は約20秒（準備を含む）、読み込み後約0.9秒。
サンプルでは6頭部を検出し1頭部に肌の補助を適用した。顔の数と判定結果で処理時間は変わる。
8192×4096の合成グレー画像による縮小・合成・取り消しの検証も合格。
導入した本体の着色表示、同じZIPのFinder Quick Lookが無着色であることを実機確認した。

v3の追加ABIは `selectModel:`（NSString: `fast` / `manga`）。ホストの直列キューで
選択→サイズ取得→推論を連続実行する。旧プラグインは選択を持たず自身のモデルで動く。
一度ロードした両モデルはプロセス終了まで保持するため、両方を使うとメモリ消費は増える。
v3の単体テストで同一インスタンスの漫画→高速→漫画を確認。クライアント側でも
8192角相当の縮小・取り消しに加え、濃さ0/100%で合成出力が変わることを確認する。
