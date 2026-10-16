import AppKit
import CryptoKit

/// Pano geçmişinin tek doğruluk kaynağı (single source of truth).
///
/// Dizilim kuralı: `items` her zaman [sabitlenmişler..., son kopyalananlar...]
/// şeklinde sıralı tutulur. Sabitlenmişler "son 10" limitinden muaftır.
///
/// Kalıcılık: Yalnızca sabitlenmiş ögeler Application Support altında hafif bir
/// JSON dosyasına yazılır; normal geçmiş oturumla birlikte yaşar.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    /// Görsel önizlemeleri (küçük thumbnail'lar) — orijinaller asla RAM'e alınmaz.
    private var thumbnailCache: [UUID: NSImage] = [:]

    private let maxUnpinned = 10

    private let pinnedFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("pinned.json")
    }()

    init() {
        loadPinned()
        // Önceki oturumdan kalan, artık referans edilmeyen görsel dosyalarını sil.
        ImageStore.shared.cleanup(keeping: Set(items.compactMap(\.imageFileName)))
    }

    // MARK: - Sınır indeksleri

    private var pinnedCount: Int {
        items.prefix(while: \.isPinned).count
    }

    private var firstUnpinnedIndex: Int { pinnedCount }

    // MARK: - Yakalama

    func addText(_ text: String) {
        if let index = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            bumpToTop(at: index)
            return
        }
        let item = ClipboardItem(
            id: UUID(), kind: .text, createdAt: Date(),
            isPinned: false, text: text, imageFileName: nil, contentHash: nil
        )
        insert(item)
    }

    func addImage(_ data: Data) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let index = items.firstIndex(where: { $0.kind == .image && $0.contentHash == hash }) {
            bumpToTop(at: index)
            return
        }
        let id = UUID()
        guard let fileName = ImageStore.shared.savePNG(data: data, id: id) else { return }
        let item = ClipboardItem(
            id: id, kind: .image, createdAt: Date(),
            isPinned: false, text: nil, imageFileName: fileName, contentHash: hash
        )
        // Önizlemeyi hemen üret; orijinal veri bu noktadan sonra yalnızca diskte.
        thumbnailCache[id] = ImageStore.shared.thumbnail(fileName: fileName)
        insert(item)
    }

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: firstUnpinnedIndex)
        trim()
    }

    /// Aynı içerik tekrar kopyalandığında listenin başına taşınır.
    private func bumpToTop(at index: Int) {
        let item = items[index]
        guard !item.isPinned else { return }
        items.remove(at: index)
        items.insert(item, at: firstUnpinnedIndex)
    }

    /// Sabitlenmemiş öge sayısını 10 ile sınırlar; düşen görsellerin dosyaları silinir.
    private func trim() {
        let unpinned = items.filter { !$0.isPinned }
        guard unpinned.count > maxUnpinned else { return }
        for item in unpinned.suffix(unpinned.count - maxUnpinned) {
            if let fileName = item.imageFileName {
                ImageStore.shared.delete(fileName: fileName)
            }
            thumbnailCache.removeValue(forKey: item.id)
            items.removeAll { $0.id == item.id }
        }
    }

    // MARK: - Kullanıcı eylemleri

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.isPinned.toggle()
        items.remove(at: index)
        if updated.isPinned {
            items.insert(updated, at: pinnedCount) // sabitlenenler bloğunun sonuna
        } else {
            items.insert(updated, at: firstUnpinnedIndex) // geçmişin başına
        }
        trim()
        savePinned()
    }

    func remove(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        if let fileName = removed.imageFileName {
            ImageStore.shared.delete(fileName: fileName)
        }
        thumbnailCache.removeValue(forKey: removed.id)
        if removed.isPinned { savePinned() }
    }

    func clearUnpinned() {
        for item in items where !item.isPinned {
            if let fileName = item.imageFileName {
                ImageStore.shared.delete(fileName: fileName)
            }
            thumbnailCache.removeValue(forKey: item.id)
        }
        items.removeAll { !$0.isPinned }
    }

    /// Seçilen ögeyi sistem panosunun tepesine yazar.
    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let fileName = item.imageFileName,
               let data = ImageStore.shared.originalData(fileName: fileName),
               let image = NSImage(data: data) {
                // NSImage, NSPasteboardWriting sayesinde PNG/TIFF temsillerini
                // hedef uygulama istedikçe sağlar; geçici decode hemen serbest kalır.
                pasteboard.writeObjects([image])
            }
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            bumpToTop(at: index)
        }
    }

    // MARK: - Önizleme

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        if let cached = thumbnailCache[item.id] { return cached }
        guard let fileName = item.imageFileName else { return nil }
        let thumbnail = ImageStore.shared.thumbnail(fileName: fileName)
        thumbnailCache[item.id] = thumbnail
        return thumbnail
    }

    // MARK: - Kalıcılık (yalnızca sabitlenmişler)

    private func savePinned() {
        let pinned = items.filter(\.isPinned)
        guard let data = try? JSONEncoder().encode(pinned) else { return }
        try? data.write(to: pinnedFileURL, options: .atomic)
    }

    private func loadPinned() {
        guard let data = try? Data(contentsOf: pinnedFileURL),
              let pinned = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = pinned
    }
}
