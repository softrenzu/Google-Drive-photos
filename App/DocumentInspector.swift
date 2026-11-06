import Foundation
import UIKit
import Vision

/// All OCR and person detection stays on the device. On any Vision error, never upload.
actor DocumentInspector {
    enum Decision: Equatable {
        case eligible
        case rejected(String)
    }

    private let documentKeywords = [
        "請求書", "領収書", "見積書", "契約書", "納品書", "発注書",
        "請求明細", "支払明細", "経費精算", "請求金額", "インボイス",
        "invoice", "receipt", "quotation", "purchase order", "tax invoice"
    ]

    private let contextKeywords = [
        "税込", "税抜", "合計", "金額", "請求", "支払", "振込", "発行",
        "住所", "日付", "会社", "御中", "円", "¥", "￥",
        "amount", "total", "tax", "date", "billing"
    ]

    private let excludedKeywords = [
        "マイナンバー", "個人番号", "運転免許証", "健康保険証",
        "パスポート", "passport", "在留カード", "身分証明書",
        "学生証", "証明写真", "my number card", "driver license"
    ]

    func inspect(_ original: Data) -> Decision {
        let faces = VNDetectFaceRectanglesRequest()
        let people = VNDetectHumanRectanglesRequest()
        people.upperBodyOnly = false

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["ja-JP", "en-US"]

        do {
            let handler = VNImageRequestHandler(data: original, options: [:])
            try handler.perform([faces, people, textRequest])

            // Reject whenever either detector sees a person. Detection is not infallible.
            if !(faces.results ?? []).isEmpty || !(people.results ?? []).isEmpty {
                return .rejected("人物または顔を検出")
            }
            let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first }
            let confident = lines.filter { $0.confidence >= 0.35 }
            let text = confident.map(\.string).joined(separator: "\n").lowercased()

            if excludedKeywords.contains(where: { text.contains($0.lowercased()) }) {
                return .rejected("身分証などの除外対象")
            }
            guard confident.count >= 4 else {
                return .rejected("書類としての文字情報が不足")
            }
            guard documentKeywords.contains(where: { text.contains($0.lowercased()) }) else {
                return .rejected("業務書類を示す語句が見つからない")
            }
            guard contextKeywords.contains(where: { text.contains($0.lowercased()) }) else {
                return .rejected("業務書類の裏付けが不足")
            }
            return .eligible
        } catch {
            return .rejected("画像判定に失敗（送信停止）")
        }
    }

    /// Convert to bounded JPEG; source HEIC, PNG and photos remain on the phone.
    func jpegForUpload(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw DocumentError.invalidImage }
        let side = max(image.size.width, image.size.height)
        guard side > 0 else { throw DocumentError.invalidImage }
        let scale = min(1.0, 3200.0 / side)
        let newSize = CGSize(width: max(1, image.size.width * scale),
                             height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.jpegData(withCompressionQuality: 0.87) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum DocumentError: LocalizedError {
    case invalidImage
    case permissionDenied
    case notConnected
    case invalidServerReply

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "画像を読み込めませんでした"
        case .permissionDenied: return "写真へのフルアクセスが必要です"
        case .notConnected: return "Googleアカウントに接続してください"
        case .invalidServerReply: return "Google Driveから不正な応答がありました"
        }
    }
}
