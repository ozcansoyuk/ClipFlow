import AppKit
import SwiftUI

// MARK: - Kayıt modeli

/// Kısayol kaydedicinin durumu. "Değiştir"e basıldığında klavye olaylarını
/// yerel bir monitor ile yakalar, geçerli ilk kombinasyonu uygular.
final class HotkeySettingsModel: ObservableObject {
    let slot: HotkeySlot
    @Published var current: HotkeyConfig
    @Published var isRecording = false
    @Published var message: String?

    /// Yeni kısayolu sisteme kaydetmeyi dener; başarısızsa `false` döner.
    var applyConfig: ((HotkeyConfig) -> Bool)?

    /// Kombinasyon başka bir ClipFlow kısayolunda kullanılıyorsa `true`.
    var isUsedElsewhere: ((HotkeyConfig) -> Bool)?

    /// Kayıt sırasında global kısayollar duraklatılır (true = kayıt başladı).
    var onRecordingStateChange: ((Bool) -> Void)?

    private var keyMonitor: Any?

    init(slot: HotkeySlot, current: HotkeyConfig) {
        self.slot = slot
        self.current = current
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard keyMonitor == nil else { return }
        isRecording = true
        message = "İstediğiniz tuş kombinasyonuna basın… (⎋ ile iptal)"
        onRecordingStateChange?(true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil // tuş başka yere gitmesin
        }
    }

    func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if isRecording {
            isRecording = false
            onRecordingStateChange?(false)
        }
    }

    func resetToDefault() {
        stopRecording()
        let config = slot.defaultConfig
        if isUsedElsewhere?(config) == true {
            message = "Varsayılan \(config.displayString) diğer ClipFlow kısayolunda kullanılıyor."
            return
        }
        if isUsedElsewhere?(config) == true {
            message = "\(config.displayString) diğer ClipFlow kısayolunda kullanılıyor — farklı bir tane deneyin."
            return
        }

        if applyConfig?(config) == true {
            current = config
            message = "Varsayılana döndü: \(config.displayString)"
        }
    }

    private func handle(_ event: NSEvent) {
        // Modifier'sız Escape: kaydı iptal et.
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            message = nil
            stopRecording()
            return
        }

        guard let config = HotkeyConfig(event: event) else {
            message = "Kısayol en az ⌘, ⌥ veya ⌃ içermelidir."
            return
        }

        if isUsedElsewhere?(config) == true {
            message = "\(config.displayString) diğer ClipFlow kısayolunda kullanılıyor — farklı bir tane deneyin."
            return
        }

        if applyConfig?(config) == true {
            current = config
            message = "Kaydedildi: \(config.displayString)"
            stopRecording()
        } else {
            message = "Bu kombinasyon kaydedilemedi — başka bir uygulama kullanıyor olabilir, farklı bir tane deneyin."
        }
    }
}

// MARK: - Görünüm

struct SettingsView: View {
    let models: [HotkeySettingsModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(models, id: \.slot) { model in
                HotkeyRow(model: model)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct HotkeyRow: View {
    @ObservedObject var model: HotkeySettingsModel

    private var hint: String {
        switch model.slot {
        case .panel: return "Kısayol, sistemin her yerinden pano panelini açar."
        case .capture: return "Kısayol, ekran görüntüsü için bölge seçimini başlatır."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.slot.title)
                .font(.headline)

            HStack(spacing: 10) {
                Text(model.isRecording ? "Bekleniyor…" : model.current.displayString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 96)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(model.isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                model.isRecording ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: 1
                            )
                    )

                Button(model.isRecording ? "İptal" : "Değiştir") {
                    model.toggleRecording()
                }

                Button("Varsayılan") {
                    model.resetToDefault()
                }
                .disabled(model.current == model.slot.defaultConfig)
            }

            Text(model.message ?? hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pencere denetleyicisi

/// Ayarlar penceresi: accessory uygulamada normal (aktifleşen) bir pencere.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let models: [HotkeySettingsModel]

    init(models: [HotkeySettingsModel]) {
        self.models = models
        super.init()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "ClipFlow Ayarları"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(models: models))
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Pencere kapanırsa yarım kalan kayıt oturumunu sonlandır.
        models.forEach { $0.stopRecording() }
    }
}
