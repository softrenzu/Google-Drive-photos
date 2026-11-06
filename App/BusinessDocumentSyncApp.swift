import BackgroundTasks
import GoogleSignIn
import SwiftUI
import UIKit

@main
@MainActor
struct BusinessDocumentSyncApp: App {
    @UIApplicationDelegateAdaptor(DocumentSyncDelegate.self) private var appDelegate
    @StateObject private var sync = SyncEngine.shared
    @StateObject private var drive = SyncEngine.shared.drive
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConsent = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        setup
                        syncControls
                        privacyNotice
                    }
                    .padding(20)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("業務書類の自動保存")
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog(
                    "Google Driveへの自動保存を開始しますか？",
                    isPresented: $showConsent,
                    titleVisibility: .visible
                ) {
                    Button("同意して自動保存を開始") {
                        sync.setAutomatic(true)
                    }
                } message: {
                    Text("請求書や領収書などの書類だけを端末内で判定します。人物を含む写真は除外しますが、人物検出には見逃しがあるため完全な保証はできません。送信先はログインしたGoogleアカウントの専用フォルダです。")
                }
            }
            .task { await sync.initialize() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await sync.scanIfEnabled() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iPhone → Google Drive", systemImage: "arrow.up.doc")
                .font(.title2.bold())
            Text("人物写真を除外し、請求書・領収書・見積書などの業務書類だけを自動保存します。")
                .foregroundStyle(.secondary)
            Label(
                sync.automatic ? "自動保存が有効です" : "自動保存はまだ開始していません",
                systemImage: sync.automatic ? "checkmark.circle.fill" : "pause.circle"
            )
            .font(.headline)
            .foregroundStyle(sync.automatic ? .green : .secondary)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("初回だけの設定").font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "1.circle.fill").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("写真へのアクセス")
                    Text(sync.photoAccessOK ? "許可済み" : "iPhone内の写真を端末内で選別するために必要です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if sync.photoAccessOK {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("許可する") { Task { await sync.requestPhotoAccess() } }
                        .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "2.circle.fill").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google Driveと連携")
                    Text(drive.email ?? "Googleアカウントを選んでログイン")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if sync.connected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("連携する") { Task { await sync.connectGoogle() } }
                        .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "3.circle.fill").font(.title3)
                Text("自動保存を開始")
                Spacer(minLength: 4)
                if sync.automatic {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("開始する") { showConsent = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!sync.canEnable)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var syncControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自動保存の状況").font(.headline)

            Text(sync.status)
                .font(.subheadline)
                .textSelection(.enabled)

            HStack(spacing: 24) {
                Label("\(sync.uploadedCount) 件保存", systemImage: "checkmark.icloud")
                Label("\(sync.skippedCount) 件除外", systemImage: "hand.raised")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if sync.automatic {
                Button {
                    Task { await sync.scan(limit: 80) }
                } label: {
                    Label(sync.running ? "確認中…" : "今すぐ確認・保存", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sync.running)

                Button("自動保存を停止する", role: .destructive) { sync.setAutomatic(false) }
                    .font(.subheadline)
            } else {
                Text("自動保存開始後は、アプリを開くと未確認の画像を検査します。バックグラウンド処理はiOSの制限を受けます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sync.connected {
                Button("Googleアカウントとの連携を解除", role: .destructive) { sync.signOut() }
                    .font(.caption)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("送信前に端末内で画像を判定", systemImage: "lock.shield")
                .font(.subheadline.bold())
            Text("人物・顔を検出した画像、身分証、判定できない画像は自動送信しません。ただし顔・人物の見逃しはゼロにできません。人物画像を絶対に送信できない場合は、自動保存を利用せず手動で選別してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("GoogleのAPIシークレットをこの画面で入力する必要はありません。認証は「連携する」から安全なGoogleログインで行います。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

final class DocumentSyncDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.rooomtech.businessdocs.refresh",
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                // Background launches may not have restored Google Sign-In yet.
                await SyncEngine.shared.drive.restore()
                let work = Task { await SyncEngine.shared.scan(limit: 20) }
                refresh.expirationHandler = { work.cancel() }
                await work.value
                SyncEngine.shared.scheduleBackground()
                refresh.setTaskCompleted(success: !work.isCancelled)
            }
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
