# BusinessDocumentSync / iPhone業務書類自動保存

**iPhoneへインストールする場合は [TestFlightによる導入手順](docs/INSTALL_IPHONE.md) を参照してください。** GitHub内のコードやシミュレーター用ビルドを直接iPhoneへインストールすることはできません。Apple Developerによる署名と配布設定が必要です。


無料で使える個人用iOSアプリ。既存の商用RooomShotとは独立したXcodeGenプロジェクトです。サブスクリプション、外部AI API、広告SDKはありません。

## 機能

- 写真ライブラリから画像を取得し、iPhone内のApple Visionで **人・顔検出** と **日本語OCR** を実行
- **請求書・領収書・見積書・契約書・納品書・発注書・経費精算・請求明細** などの語句が検出され、書類としての条件を満たす画像のみ自動選別
- 顔・人が検出された画像、運転免許証など身分証、OCR判定が曖昧な画像はアップロードしない
- Google Driveの `iPhone_Business_Documents` フォルダへ直接アップロード。OAuthの `drive.file` 権限のみ
- アプリ起動・写真変更時に新着画像を調査。バックグラウンド更新をiOSへリクエスト（実行時刻の保証なし）
- アップロード済みIDを端末内に保持し、Drive側でもアプリ固有のハッシュIDで重複確認
- 自動アップロードは初期状態OFF。本人がアクセス権と送信先を確認後にONにする
- 写真中のOCR内容や写真本体を自社サーバー・外部AIサービスへ送信しない

**重要：人物検出は完全ではありません。** 顔が小さい・写真に印刷されている・一部だけ写っていると見逃す場合があります。業務秘密や人物写真の流出を絶対に許容できない場合は、自動送信をOFFにして、送信前に人が選別してください。アプリの初期設定は送信OFFです。

## 必要環境

- iOS 17以上の実機iPhone
- Xcode 26以降を実行できるMac（WindowsだけでiOSネイティブアプリの署名・インストールはできません）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Google Cloudプロジェクト、Google Drive APIを有効化したiOS OAuthクライアント
- Apple ID / 端末署名（無料のPersonal Teamでは再署名等の制約あり）

## 導入

1. Macでこのリポジトリをチェックアウトし、ターミナルでリポジトリのルートへ移動
2. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` を実行
3. Google Cloud ConsoleでDrive APIを有効化し、OAuth同意画面を設定。iOSのBundle IDは `com.rooomtech.businessdocumentsync` と一致させる
4. `Config/Secrets.xcconfig` に **iOS OAuthクライアントID**、**逆順クライアントID**、**Apple Team ID** を入力する。OAuthスコープは `https://www.googleapis.com/auth/drive.file` のみ
5. `swift scripts/generate_icon.swift`、`xcodegen generate` を順に実行し `open BusinessDocumentSync.xcodeproj` で開く
6. Xcodeで開発チームを指定し、iPhoneを接続してビルド・実機実行
7. 初回起動で「写真へのフルアクセス」を許可し、Googleアカウントにログイン。接続先を確認してから「自動同期」をON
8. 「今すぐ検査」を押して動作を確認。Google Driveに `iPhone_Business_Documents` が作成される

## iOSのバックグラウンド制約

PhotoKitの変更通知はアプリが動作している間の通知です。BGTaskSchedulerの更新はiOSが実行機会を判断するため、**写真撮影のたびに即時アップロードする保証はありません**。アプリ起動時には未処理画像を再走査します。

iOS 26.1以降にはPhotoKitの新しいBackground Resource Upload Extensionがありますが、この実装はOAuth更新やDriveメタデータ検証を伴うため、現段階では使用していません。強制終了されたアプリや省電力設定によってはバックグラウンド更新が実行されない場合があります。

## 安全設計・制限

- 自動同期ONより前の30日分までが初回走査の対象です。既存の全画像を無条件にアップロードしません。
- 1回の検査で最大80枚を処理します。写真が多い場合は再度「今すぐ検査」を押してください。
- エラー時はアップロードせず、次の実行で再試行します。
- iOSのVision検出には偽陰性があります。顔を含む書類も絶対にアップロードしない保証はできません。
- Google側のOAuth設定やCloud費用規約はGoogleアカウントの設定に依存します。アプリ自体に課金処理はありません。
- GitHub ActionsのiOSシミュレーター用ビルドは成功しています。ただし**TestFlight実配布・iPhone実機インストール・Google実アカウントへの送信試験は未実施**です。

## 参考文書

- [Apple Vision](https://developer.apple.com/documentation/vision)
- [Apple PhotoKit Background Resource Upload](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background)
- [Google iOS Sign-In](https://developers.google.com/identity/sign-in/ios/api-access)
- [Google Drive files.create](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/create)
