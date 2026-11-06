# iPhone向けWebアプリ / 業務書類をGoogle Driveへ

## iPhoneでの操作

1. Renderに公開したWebアプリのURLをSafariで開く。
2. Google Cloudの**ウェブアプリケーション用OAuthクライアントID**を入力し、「Googleアカウントで連携する」を押す。シークレットキーは入力しない。
3. 「写真ライブラリから選ぶ」→ 写真を選択 →「選んだ写真を判定」を押す。
4. iPhone内で人物検出と日本語OCRを実行。書類候補のプレビューを確認し、「Google Driveに保存」を押す。
5. 初回はSafariの共有メニューで**「ホーム画面に追加」→「Webアプリとして開く」をオン→「追加」**。ホーム画面に「書類保存」の専用アイコンが表示され、次からアイコンを1回タップして起動できます。アプリとして起動したときはSafariのアドレスバーを表示しません。

**自動ライブラリ同期はできません。** iPhoneのSafari/PWAは写真ライブラリへのバックグラウンド全件アクセスを許可しておらず、写真の選択は毎回必要です。iOSネイティブ版とは機能が異なります。

Appleのホーム画面への追加はブラウザから自動実行できないため、初回の追加操作だけは利用者が行う必要があります。追加後は毎回SafariでURLを探す必要はありません。

## Google Cloud設定（初回のみ）

1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials) でプロジェクトを作成し、**Google Drive API** を有効にする。
2. OAuth同意画面の設定を行う。公開前のテスト状態で使う場合、自分のGoogleアカウントをテストユーザーとして追加する。
3. OAuthクライアントの種類を**「ウェブ アプリケーション」**にして作成する。
4. **承認済みのJavaScript生成元**に `https://rooomtech-business-document-sync.onrender.com` を追加する。パスを含めず、生成元だけ指定する。
5. クライアントID（`12345-xxxxx.apps.googleusercontent.com`）をコピーしてWebアプリの設定欄へ貼り付ける。
6. OAuthスコープは `https://www.googleapis.com/auth/drive.file`。ユーザーは自分のGoogleアカウントでログインする。
7. Google OAuthクライアントの**シークレット**をWebアプリに貼り付けたり、GitHubへコミットしてはいけません。

## 安全設計

- 画像を選択するまでWebアプリは写真ライブラリへアクセスできない。
- Google Driveへの送信前にブラウザ内でCOCO-SSD人物検出・BlazeFace顔検出・Tesseract OCRを使う。モデルと日本語辞書はインターネット経由で読み込むが、写真画像を判定APIへアップロードしない。
- 判定プログラムが読み込めない・エラーになる画像は送信しない。
- 請求書など所定の語句が見つかり、人物が検出されなかった写真だけを候補にする。
- 最後に**必ずユーザーがサムネイルを見て、送信を承認**する。
- 顔や人物をAIが見逃す可能性は残る。完全な人物写真除外は保証できない。
- Google Driveの権限は`drive.file`のみ。アクセストークンはメモリだけに保持し、リロード時は再認証が必要。
- OAuthクライアントIDと作成したフォルダのIDはブラウザのローカルストレージに保存する。写真やアクセストークンは保存しない。
- Google Driveへ送信される画像はメタデータを除去したJPEGへ再変換する。
- 初回に利用する人物判定モデル、OCRライブラリは外部CDNから読み込む。CDN障害時は判定不可・アップロード不可。

## 公開

メイン公開先はRenderの静的Webサイト：

`https://rooomtech-business-document-sync.onrender.com/`

`web/`以下を公開し、GitHub main更新時に自動デプロイする。


GitHub Pagesはこのリポジトリでは有効になっていないため、Web版はRenderに公開しています。

## 開発

`node --check web/app.js`で構文チェック。静的Webアプリなのでビルド不要です。

このWebアプリは既存のiPhone用Swiftアプリを置き換えず、同じ新しいリポジトリに独立して配置しています。旧RooomShotリポジトリには変更を加えていません。
