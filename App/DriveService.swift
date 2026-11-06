import Foundation
import GoogleSignIn
import UIKit

/// Google Drive connection. No backend, API keys or subscription service.
@MainActor
final class DriveService: ObservableObject {
    static let scope = "https://www.googleapis.com/auth/drive.file"
    @Published private(set) var email: String?
    private let session: URLSession = .shared
    private let defaults = UserDefaults.standard

    private var folderKey: String {
        "businessDocs.folder." + (email ?? "signedOut")
    }

    func restore() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in
                continuation.resume()
            }
        }
        updateEmail()
    }

    func signIn() async throws {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !value.isEmpty, !value.contains("REPLACE_WITH") else {
            throw DriveError.configuration
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            throw DriveError.presenter
        }
        let presenter = Self.topmost(root)
        let _: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [Self.scope]
            ) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: DocumentError.notConnected) }
            }
        }
        updateEmail()
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        email = nil
    }

    private func updateEmail() {
        guard let user = GIDSignIn.sharedInstance.currentUser,
              user.grantedScopes?.contains(Self.scope) == true else {
            email = nil
            return
        }
        email = user.profile?.email
    }

    private static func topmost(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController { return topmost(presented) }
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController { return topmost(visible) }
        if let tabs = controller as? UITabBarController,
           let selected = tabs.selectedViewController { return topmost(selected) }
        return controller
    }

    private func token() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw DocumentError.notConnected
        }
        let updated: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: DocumentError.notConnected) }
            }
        }
        guard updated.grantedScopes?.contains(Self.scope) == true else {
            throw DocumentError.notConnected
        }
        return updated.accessToken.tokenString
    }

    private func jsonRequest(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 40
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
        return data
    }

    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DocumentError.invalidServerReply
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw DriveError.http(http.statusCode, message)
        }
    }

    private func folderID() async throws -> String {
        if let saved = defaults.string(forKey: folderKey), !saved.isEmpty { return saved }
        let url = URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!
        let meta: [String: String] = [
            "name": "iPhone_Business_Documents",
            "mimeType": "application/vnd.google-apps.folder"
        ]
        let data = try await jsonRequest(url, method: "POST", body: JSONSerialization.data(withJSONObject: meta))
        let folder = try JSONDecoder().decode(DriveItem.self, from: data)
        defaults.set(folder.id, forKey: folderKey)
        return folder.id
    }

    private func fileExists(_ sourceHash: String) async throws -> Bool {
        var parts = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        parts.queryItems = [
            URLQueryItem(name: "q", value: "appProperties has { key='sourceHash' and value='\(sourceHash)' } and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id),nextPageToken"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        let data = try await jsonRequest(parts.url!)
        return !(try JSONDecoder().decode(DriveList.self, from: data).files.isEmpty)
    }

    /// Idempotency: check appProperties before starting a new upload.
    func upload(_ image: Data, fileName: String, sourceHash: String) async throws {
        if try await fileExists(sourceHash) { return }
        let destination = try await folderID()
        var parts = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files")!
        parts.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: "id,name")
        ]

        let metadata: [String: Any] = [
            "name": fileName,
            "mimeType": "image/jpeg",
            "parents": [destination],
            "appProperties": ["sourceHash": sourceHash]
        ]
        var start = URLRequest(url: parts.url!)
        start.httpMethod = "POST"
        start.timeoutInterval = 60
        start.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        start.setValue("image/jpeg", forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(image.count), forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (initial, response) = try await session.data(for: start)
        try Self.check(response, data: initial)
        guard let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else {
            throw DocumentError.invalidServerReply
        }

        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.timeoutInterval = 180
        put.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        put.setValue(String(image.count), forHTTPHeaderField: "Content-Length")
        let (finalData, finalResponse) = try await session.upload(for: put, from: image)
        try Self.check(finalResponse, data: finalData)
        _ = try JSONDecoder().decode(DriveItem.self, from: finalData)
    }

    private struct DriveItem: Decodable { let id: String }
    private struct DriveList: Decodable { let files: [DriveItem] }
}

enum DriveError: LocalizedError {
    case configuration
    case presenter
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .configuration: return "GoogleのOAuthクライアントIDを設定してください"
        case .presenter: return "Googleログイン画面を開けません"
        case .http(let status, let message): return "Google Drive エラー \(status): \(message)"
        }
    }
}
