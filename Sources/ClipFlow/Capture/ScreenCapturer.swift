import AppKit
import ScreenCaptureKit

/// Tüm ekranların o anki görüntüsünü ScreenCaptureKit ile tek seferde alır.
/// Overlay bu "donmuş" görüntüleri gösterir; seçim ve işaretleme onların
/// üzerinde yapılır (Lightshot davranışı).
enum ScreenCapturer {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// İlk çağrıda sistem izin diyaloğunu gösterir; sonraki çağrılarda
    /// sessizce mevcut durumu döndürür.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openPermissionSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Ekran kimliği → tam çözünürlüklü (Retina piksel) görüntü.
    /// Kullanıcının o an gördüğü her şey yakalanır; imleç hariç.
    static func captureAllDisplays() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int(filter.contentRect.width * scale)
            config.height = Int(filter.contentRect.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            result[display.displayID] = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        }
        return result
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
