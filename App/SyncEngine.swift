import BackgroundTasks
import CryptoKit
import Foundation
import Photos
import UIKit

@MainActor
final class SyncEngine: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = SyncEngine()
    static let backgroundIdentifier = "com.rooomtech.businessdocs.refresh"

    let drive = DriveService()
    private let inspector = DocumentInspector()
    private var observedAssets: PHFetchResult<PHAsset>?
    private let defaults = UserDefaults.standard

    @Published private(set) var automatic = false
    @Published private(set) var running = false
    @Published private(set) var status = "未設定"
    @Published private(set) var uploadedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var errorCount = 0

    var photoAccessOK: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }
    var connected: Bool { drive.email != nil }
    var canEnable: Bool { photoAccessOK && connected }

    private override init() {
        super.init()
        automatic = defaults.bool(forKey: "documentSync.enabled")
        PHPhotoLibrary.shared().register(self)
    }

    func initialize() async {
        await drive.restore()
        if automatic && canEnable { scheduleBackground(); await scan(limit: 80) }
    }

    func requestPhotoAccess() async {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if permission == .authorized {
            status = "写真へのフルアクセスが許可されました"
        } else {
            setAutomatic(false)
            status = "フルアクセスが必要です。設定アプリから変更してください"
        }
    }

    func connectGoogle() async {
        do {
            try await drive.signIn()
            status = "Google Driveに接続しました"
        } catch {
            status = error.localizedDescription
        }
    }

    func signOut() {
        setAutomatic(false)
        drive.signOut()
        status = "Googleからログアウトしました"
    }

    func setAutomatic(_ value: Bool) {
        guard !value || canEnable else {
            automatic = false
            status = "写真へのフルアクセスとGoogleログインが必要です"
            return
        }
        automatic = value
        defaults.set(value, forKey: "documentSync.enabled")
        if value {
            status = "自動同期を有効化しました"
            scheduleBackground()
            Task { await scan(limit: 80) }
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
            status = "自動送信は停止しています"
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            await SyncEngine.shared.scanIfEnabled()
        }
    }

    func scanIfEnabled() async {
        if automatic { await scan(limit: 80) }
    }

    /// Rejected images are remembered but never uploaded; failures are retried next time.
    func scan(limit: Int) async {
        guard automatic, canEnable, !running else { return }
        running = true
        defer { running = false }

        let account = drive.email ?? ""
        let key = "documentSync.handled.\(account)"
        var handled = Set(defaults.stringArray(forKey: key) ?? [])
        let since = defaults.object(forKey: "documentSync.start.\(account)") as? Date
            ?? Date().addingTimeInterval(-30 * 24 * 60 * 60)
        if defaults.object(forKey: "documentSync.start.\(account)") == nil {
            defaults.set(since, forKey: "documentSync.start.\(account)")
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", since as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        observedAssets = result // Retain the fetch result so PhotoKit can notify us about changes.
        var pending: [PHAsset] = []
        result.enumerateObjects { asset, _, stop in
            if !handled.contains(asset.localIdentifier) {
                pending.append(asset)
                if pending.count >= limit { stop.pointee = true }
            }
        }

        if pending.isEmpty {
            status = "未処理の画像はありません"
            scheduleBackground()
            return
        }

        var stoppedOnError = false
        var inspectedInThisScan = 0
        for (index, asset) in pending.enumerated() {
            if Task.isCancelled || !automatic || !connected { break }
            inspectedInThisScan += 1
            status = "端末内で書類を検査中 \(index + 1)/\(pending.count)"
            do {
                let bytes = try await loadPhoto(asset)
                let decision = await inspector.inspect(bytes)
                switch decision {
                case .rejected:
                    skippedCount += 1
                    handled.insert(asset.localIdentifier)
                    defaults.set(Array(handled), forKey: key)
                case .eligible:
                    let jpeg = try await inspector.jpegForUpload(from: bytes)
                    let hash = Self.hashID(asset.localIdentifier)
                    let dateString = Self.safeTimestamp(asset.creationDate ?? Date())
                    let name = "BusinessDocument_\(dateString)_\(hash.prefix(12)).jpg"
                    // Last safety gate before network transmission.
                    guard automatic && connected else { break }
                    try await drive.upload(jpeg, fileName: name, sourceHash: hash)
                    uploadedCount += 1
                    handled.insert(asset.localIdentifier)
                    defaults.set(Array(handled), forKey: key)
                }
            } catch {
                errorCount += 1
                stoppedOnError = true
                status = "送信停止: \(error.localizedDescription)（あとで再試行）"
                // Stop on network/auth or image-loading failure; do not mark as processed.
                break
            }
        }

        if !stoppedOnError {
            status = "検査完了。今回の検査枚数: \(inspectedInThisScan)（累計送信 \(uploadedCount) 件）"
        }
        scheduleBackground()
    }

    private func loadPhoto(_ asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: DocumentError.invalidImage)
                }
            }
        }
    }

    private static func hashID(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func safeTimestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return fmt.string(from: date)
    }

    func scheduleBackground() {
        guard automatic && canEnable else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 2)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            status = "バックグラウンドの予約に失敗: \(error.localizedDescription)"
        }
    }
}
