import AppKit
import ImageIO

/// Görsellerin disk üzerindeki yaşam döngüsünü yönetir.
///
/// RAM optimizasyonu stratejisi:
/// - Kopyalanan orijinal görsel ANINDA diske (PNG) yazılır, bellekte tutulmaz.
/// - Arayüz için önizleme, ImageIO'nun `CGImageSourceCreateThumbnailAtIndex` API'si ile
///   üretilir — bu API görseli tam çözünürlükte decode ETMEDEN, doğrudan
///   küçültülmüş halde okur (downsampling). Böylece 50 MB'lık bir ekran
///   görüntüsü bile RAM'de yalnızca ~100 KB'lık bir thumbnail olarak yaşar.
/// - Orijinal veri yalnızca yapıştırma anında diskten okunur ve hemen bırakılır.
final class ImageStore {
    static let shared = ImageStore()

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ClipFlow/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Pano verisini PNG olarak diske kaydeder, dosya adını döndürür.
    func savePNG(data: Data, id: UUID) -> String? {
        let pngData: Data
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            // Zaten PNG — decode etmeden doğrudan yaz.
            pngData = data
        } else if let rep = NSBitmapImageRep(data: data),
                  let converted = rep.representation(using: .png, properties: [:]) {
            // TIFF vb. formatlar tek seferlik dönüştürülür (geçici bellek, hemen serbest kalır).
            pngData = converted
        } else {
            return nil
        }

        let name = id.uuidString + ".png"
        do {
            try pngData.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Yapıştırma anında orijinal veriyi diskten okur.
    func originalData(fileName: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    /// Tam decode yapmadan küçük önizleme üretir.
    func thumbnail(fileName: String, maxPixelSize: CGFloat = 480) -> NSImage? {
        let url = directory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// Açılışta, önceki oturumdan kalan sahipsiz (sabitlenmemiş) görselleri temizler.
    func cleanup(keeping fileNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !fileNames.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}
