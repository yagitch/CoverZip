# AI自動着色プラグイン

CoverZip本体とは独立してビルド・導入する `AIColorizer.bundle`。
推論コード・Core MLモデルはアプリへ埋め込まず、App Group内の
`Library/Application Support/CoverZip/PlugIns/` に配置する。
メニューバー「表示 → AI自動着色（プラグイン）」で切り替える。
本体の通常の自動着色は残し、AIがオンの場合はAIを優先する。
Finder Quick Lookではどちらも実行しない。

## 処理と境界

- 本体のQLPreviewViewだけがURL fragment `coverzip-native-viewer` を渡す。
  拡張は印のないプレビューを無着色にする。同一ファイルを本体とFinderで同時に開いて検証済み。
- プラグインABIはObjective-Cの `CZAIColorizerPlugin.colorizeBGRA:`。
  入出力はNSDataの **256×256、BGRA8、262144バイト**。異なるサイズは拒否する。
- 原画像は呼び出し側で縮小してから渡す。core/tailの双方を256×256で実行する。
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
