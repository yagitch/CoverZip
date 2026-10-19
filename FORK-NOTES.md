# このフォークの変更

手動で最終ページ（見開きの場合は最終見開き）からさらに進むと、1ページ目へ戻ります。
先頭から戻る操作と、スライドショーの末尾停止は従来どおりです。
画像が0枚または1枚の場合はページ変更を行いません。

本体の内蔵ビューアとFinderのQuick Lookは共通の `ImageManager` を使用します。
キー入力・アプリ識別子・設定キーは変更していません。

## ローカル署名

このフォークのApp Groupは `6KCX8JYZB7.com.yagitch.CoverZip` です。
作者のApp Groupは別チームで使えないため、利用者の合意に基づいて本体・全拡張・
KeyHelper・共有設定定義を揃えて変更しています。旧グループの読書履歴は自動移行しません。

利用者のApple Development証明書を使い、macOSのチームID接頭辞方式で署名します。
元のアプリとKarabiner設定は `.local-backup/20261019/` に退避済みです。
導入先は `/Applications/CoverZip.app`、改修版のビルド番号は30です。
公式版で改修が上書きされないよう、設定画面の自動アップデート確認をオフにします。
署名者が変わる初回導入時は、KeyHelperのアクセシビリティ権限とログイン項目を
登録し直します。Karabinerの設定変更は不要です。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CoverZip.xcodeproj -scheme CoverZip -configuration Release \
  -derivedDataPath .build-local build DEVELOPMENT_TEAM=6KCX8JYZB7 \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
  PROVISIONING_PROFILE_SPECIFIER= REGISTER_APP_GROUPS=NO CURRENT_PROJECT_VERSION=30
```

境界条件のテスト: `python3 tests/check_page_navigation.py`
これは実装メソッドをSwiftで実行する単体検証です。アプリのビルド、署名、
Quick Look登録、本体とFinderでの実キーボード操作は別途実機検証が必要です。
