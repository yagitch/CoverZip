# このフォークの変更

手動で最終ページ（見開きの場合は最終見開き）からさらに進むと、1ページ目へ戻ります。
先頭から戻る操作と、スライドショーの末尾停止は従来どおりです。
画像が0枚または1枚の場合はページ変更を行いません。

本体の内蔵ビューアとFinderのQuick Lookは共通の `ImageManager` を使用します。
キー入力・アプリ識別子・設定キーは変更していません。

## ウインドウと開始ページ（ビルド31）

Quick Look・内蔵ビューアとも、毎回1ページ目から開きます。
読書位置の保存・復元を無効化しています。既存の履歴データは削除しません。

「ウィンドウサイズ・位置を復元」が有効な場合、通常ウインドウのサイズを
ファイル共通で保持します。本体は外枠サイズを保存・復元し、Finder Quick Lookは
既存のKeyHelperが実ウインドウのサイズを保存・復元します。両者は同じ保存先を使います。
Quick Lookでの機能にはKeyHelperの有効化と既存のアクセシビリティ権限が必要です。
フルスクリーンの寸法は通常サイズに上書きしません。

ビルド32では、拡張からの希望サイズ通知を初回だけに限定しています。
本文サイズを繰り返し希望サイズへ戻す循環を避け、Quick Lookでは位置も共用します。
起動アニメーション後に外枠を復元し、起動時のOSの補正結果は保存値へ書き戻しません。

ビルド32は実機で位置ずれ・累積縮小の解消を確認済みです。
ビルド33では復元前の0.75秒待機を撤廃し、Quick Look検出間隔を0.05秒に短縮しました。
復元は検出直後に行い、保存開始前だけ0.75秒待って起動時の変化を除外します。

## ローカル署名

このフォークのApp Groupは `6KCX8JYZB7.com.yagitch.CoverZip` です。
作者のApp Groupは別チームで使えないため、利用者の合意に基づいて本体・全拡張・
KeyHelper・共有設定定義を揃えて変更しています。旧グループの読書履歴は自動移行しません。

利用者のApple Development証明書を使い、macOSのチームID接頭辞方式で署名します。
元のアプリとKarabiner設定は `.local-backup/20261019/` に退避済みです。
導入先は `/Applications/CoverZip.app`、改修版のビルド番号は33です。
公式版で改修が上書きされないよう、設定画面の自動アップデート確認をオフにします。
署名者が変わる初回導入時は、KeyHelperのアクセシビリティ権限とログイン項目を
登録し直します。Karabinerの設定変更は不要です。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CoverZip.xcodeproj -scheme CoverZip -configuration Release \
  -derivedDataPath .build-local build DEVELOPMENT_TEAM=6KCX8JYZB7 \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
  PROVISIONING_PROFILE_SPECIFIER= REGISTER_APP_GROUPS=NO CURRENT_PROJECT_VERSION=33
```

境界条件のテスト: `python3 tests/check_page_navigation.py`
これは実装メソッドをSwiftで実行する単体検証です。アプリのビルド、署名、
Quick Look登録、本体とFinderでの実キーボード操作は別途実機検証が必要です。
