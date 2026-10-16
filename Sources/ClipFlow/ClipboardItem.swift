import Foundation

/// Tek bir pano kaydı. Görseller RAM'de tutulmaz; diskteki dosyaya
/// `imageFileName` ile referans verilir, arayüz için küçük önizleme
/// `ClipboardStore` içindeki cache'ten gelir.
struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    var isPinned: Bool

    /// Metin ögeleri için içerik.
    var text: String?

    /// Görsel ögeleri için diskteki PNG dosyasının adı (Application Support altında).
    var imageFileName: String?

    /// Görsel ögelerde tekrar kopyalamayı (duplicate) yakalamak için SHA-256 özeti.
    var contentHash: String?

    var previewText: String {
        switch kind {
        case .text:
            return (text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ⏎ ")
        case .image:
            return "Resim"
        }
    }
}
