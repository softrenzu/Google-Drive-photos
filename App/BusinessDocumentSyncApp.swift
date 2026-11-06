import BackgroundTasks
import GoogleSignIn
import SwiftUI
import UIKit

@main
@MainActor
struct BusinessDocumentSyncApp: App {
    @UIApplicationDelegateAdaptor(DocumentSyncDelegate.self) private var appDelegate
    @StateObject private var sync = SyncEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("接続") {
                        HStack {
                            Label("写真ライブラリ", systemImage: "photo.on.rectangle")
                            Spacer()
                            Text(sync.photoAccessOK ? "フルアクセス済み" : "未許可")
                                .foregroundStyle(.secondary)
                        }
                        Button("写真へのアクセスを許可") {
                            Task { await sync.requestPhotoAccess() }
                        }
                        HStack {
                            Label("Google Drive", systemImage: "externaldrive")
                            Spacer()
                            Text(sync.drive.email ?? "未接続")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if sync.connected {
                            Button("Googleからログアウト", role: .destructive) { sync.signOut() }
                        } else {
                            Button("Googleアカウントに接続") {
                                Task { await sync.connectGoogle() }
                            }
                        }
                    }

                    Section("業務書類の自動同期") {
                        Toggle("自動同期を有効にする", isOn: Binding(
                            get: { sync.automatic },
                            set: { sync.setAutomatic($0) }
                        ))
                        .disabled(!sync.canEnable && !sync.automatic)

                        Button {
                            Task { await sync.scan(limit: 80) }
                        } label: {
                            Label(sync.running ? "検査中..." : "今すぐ検査", systemImage: "doc.text.viewfinder")
                        }
                        .disabled(!sync.automatic || sync.running)
                        Text("新しい写真と直近30日間の画像を端末内で検査します。1回あたり最大80枚です。自動同期はiOSが許可したタイミングで実行されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("検査状況") {
                        LabeledContent("Google Driveへ送信", value: "\(sync.uploadedCount) 件")
                        LabeledContent("対象外として除外", value: "\(sync.skippedCount) 件")
                        LabeledContent("エラー", value: "\(sync.errorCount) 件")
                        Text(sync.status)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    Section("プライバシー") {
                        Label("人物・顔を検出した画像は送信しません", systemImage: "person.crop.circle.badge.xmark")
                        Label("身分証・判定不能な画像は自動送信しません", systemImage: "hand.raised")
                        Label("画像判定はiPhone内で実行します", systemImage: "iphone")
                        Text("注意：人物検出には見逃しがあります。人物画像を絶対に送れない場合は自動同期をOFFにしてください。画像中の個人情報や秘密情報の自動除去は行いません。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .navigationTitle("業務書類自動保存")
            }
            .task { await sync.initialize() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await sync.scanIfEnabled() }
                }
            }
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
