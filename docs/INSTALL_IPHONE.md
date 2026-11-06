# iPhoneにアプリをインストールする（TestFlight）

このリポジトリは**業務書類の写真だけをGoogle Driveに自動転送する無料のiPhoneアプリ**です。
App Storeの一般公開は必要ありません。自分のiPhoneへ導入するにはTestFlightを使用します。

## 状態

- SwiftUIのアプリ本体とGoogle Drive API連携を実装
- GitHub ActionsでiOSシミュレーター向けビルド確認
- iPhone用の署名・IPA出力・TestFlightへのアップロード用GitHub Actionsを用意
- **Apple Developer側の認証・証明書・Google OAuth設定が未登録の場合、まだTestFlightに配布できません**
- 人物検出には見逃しがあり、絶対に人物写真が送信されない保証はありません
- iOSはバックグラウンド実行を制御するため、撮影直後の100%リアルタイム同期はできません

## インストールまでの最短手順（原則一度だけ）

### A. Apple Developer側の設定

1. [Apple Developer Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) で新しいApp ID `com.rooomtech.businessdocumentsync` を登録する。
2. [App Store Connect](https://appstoreconnect.apple.com/apps) に上記Bundle IDのiOSアプリを作る。表示名は「業務書類自動保存」など。
3. Apple Distribution証明書（.p12）と、上記Bundle ID用 **App Store配布用Provisioning Profile**（.mobileprovision）を用意する。既存のApple Distribution証明書を使う場合も、**このアプリ専用のProvisioning Profile** は必要。
4. App Store Connectの「ユーザとアクセス」→「統合」→App Store Connect APIでAPIキー（.p8）、Key ID、Issuer IDを取得する。
5. Apple Developer Team IDを確認する。

Apple Developer Programへの加入が必要。個人の無料Apple IDだけではTestFlight配布はできません。

### B. Google Cloud側の設定

1. [Google Cloud Console](https://console.cloud.google.com/apis/library/drive.googleapis.com) でGoogle Drive APIを有効化。
2. OAuth同意画面を設定する。必要なら自分のGoogleアカウントをテストユーザーに登録する。
3. 「認証情報」から iOS OAuthクライアントを新規作成し、Bundle IDを **`com.rooomtech.businessdocumentsync`** とする。
4. クライアントID（`...apps.googleusercontent.com`）と逆順クライアントID（`com.googleusercontent.apps....`）を取得。
5. 利用するスコープは `https://www.googleapis.com/auth/drive.file` に限定する。

### C. このGitHubリポジトリにSecretを登録する

[このリポジトリのGitHub Actions Secrets](https://github.com/softrenzu/Google-Drive-photos/settings/secrets/actions) を開き、下記を追加する。**ファイルをリポジトリへコミットしない。ChatGPTの会話へ鍵を貼り付けない。**

| Secret名 | 入力値 |
|---|---|
| `GOOGLE_CLIENT_ID` | Google CloudのiOS OAuthクライアントID |
| `GOOGLE_REVERSED_CLIENT_ID` | 同じOAuthクライアントの逆順ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `BUILD_CERTIFICATE_BASE64` | Apple Distribution証明書の .p12 ファイルをbase64エンコードした文字列 |
| `P12_PASSWORD` | .p12書き出し時のパスワード |
| `BUILD_PROVISION_PROFILE_BASE64` | このBundle IDのApp Store用 .mobileprovision のbase64文字列 |
| `KEYCHAIN_PASSWORD` | GitHub Actionsの一時キーチェーン用に作成したランダムな文字列 |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_API_KEY_BASE64` | App Store Connectの .p8 API秘密鍵ファイルをbase64エンコードした文字列 |

Macでファイルをbase64化する例：

```bash
base64 < DistributionCertificate.p12 | tr -d '\n'
base64 < BusinessDocumentSync.mobileprovision | tr -d '\n'
base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
```

Base64は暗号化ではありません。GitHub Secretsとして登録し、その他の場所へ公開しないでください。

### D. GitHubからTestFlightへ送る

1. [Publish signed iPhone app to TestFlight](https://github.com/softrenzu/Google-Drive-photos/actions/workflows/testflight.yml) を開く。
2. 「Run workflow」を押し、`confirm_distribution` をONにして開始する。
3. 緑のチェックが表示されれば、署名済みIPAがApp Store Connectへアップロードされています（Apple側の処理は別途必要）。
4. [App Store Connect](https://appstoreconnect.apple.com/apps) → 該当アプリ → TestFlightで、処理済みビルドを確認し、自分のApple IDを内部テスターとして追加する。

本人がApp Store ConnectのAccount Holder/Admin/App Manager等の内部テスト可能な権限を持っている必要があります。外部テスターは別途Appleの審査が必要になる場合があります。

### E. iPhoneにインストールする

1. iPhoneに[無料のTestFlight](https://apps.apple.com/jp/app/testflight/id899247664)をインストールする。
2. App Store Connectの招待メールをiPhoneで開き「TestFlightで表示」を選ぶ。
3. 「承諾」→「インストール」。
4. 「業務書類自動保存」を開き、写真のフルアクセスを許可、Googleアカウントでログインする。
5. 最初は**自動同期をOFF**にしたまま動作を確認する。顔・人物の誤判定リスクを許容できる場合のみ自動同期をONにする。

## 開発／配布の区別

- [iOS Build](../.github/workflows/ios-build.yml): iOSシミュレーターでビルド確認。iPhoneへインストールできるアプリは出力しません。
- [TestFlight](../.github/workflows/testflight.yml): Apple Distribution署名とApp Store Connectアップロード。10個のSecretとAppleの初期設定が必要。
- TestFlightの各ビルドは有効期間90日。継続使用には新しいビルドの配信が必要です。
- TestFlightの招待URLはApple側のテストグループで作成されます。アプリのコードだけで発行できません。

## 写真の安全性について

このアプリはApple Visionで端末内の人物・顔検出とOCRを行い、該当条件を満たす画像だけをDriveに送ります。顔検出の偽陰性はゼロではありません。個人情報のある契約書や請求書が自動的にDriveへ送られる可能性もあるため、送信先Googleアカウントの選択と共有権限を確認してください。
