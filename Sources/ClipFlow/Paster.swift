import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Aktif uygulamaya otomatik yapıştırma.
///
/// Panel `.nonactivatingPanel` olduğu için hedef uygulama odağı hiç kaybetmez;
/// panoya yazdıktan kısa bir gecikme sonrası sentetik ⌘V olayı gönderilir.
/// CGEvent ile klavye simülasyonu macOS'te Erişilebilirlik (Accessibility)
/// izni gerektirir.
enum Paster {
    /// İzin yoksa sistem ayarlarına yönlendiren diyaloğu tetikler.
    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    /// Kısa bir gecikmeyle ⌘V tuş kombinasyonunu aktif uygulamaya gönderir.
    /// İzin verilmemişse içerik yine de panodadır; kullanıcı elle ⌘V yapabilir.
    static func sendCmdV(after delay: TimeInterval = 0.12) {
        guard ensureAccessibilityPermission(prompt: true) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            )
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
