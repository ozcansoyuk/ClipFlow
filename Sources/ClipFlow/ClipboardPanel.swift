import AppKit

/// İmlecin yanında açılan hafif panel.
///
/// Kritik detay — `.nonactivatingPanel`: panel klavye olaylarını alabilmek için
/// "key window" olur ama UYGULAMAYI AKTİFLEŞTİRMEZ. Böylece kullanıcının
/// çalıştığı uygulama ön planda kalır ve seçim sonrası gönderilen ⌘V doğru
/// hedefe gider (Spotlight'ın çalışma prensibiyle aynı).
final class ClipboardPanel: NSPanel {
    /// Panel dışına tıklanınca (key durumu kaybedilince) kapatma.
    var onResignKey: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    // Borderless pencereler varsayılan olarak key olamaz; klavye navigasyonu için şart.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
