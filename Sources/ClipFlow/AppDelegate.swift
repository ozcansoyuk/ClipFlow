import AppKit
import ServiceManagement
import SwiftUI

/// Tüm bileşenleri birbirine bağlayan merkez: durum çubuğu ögesi, pano
/// izleyici, global kısayollar, panel ve ekran görüntüsü.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ClipboardStore()
    private let monitor = PasteboardMonitor()
    private let hotkey = HotkeyManager()
    private var panelController: PanelController!
    private let captureController = CaptureController()

    private var hotkeyConfigs = Dictionary(uniqueKeysWithValues: HotkeySlot.allCases.map { ($0, HotkeyConfig.load($0)) })
    private var settingsModels: [HotkeySettingsModel] = []
    private var settingsController: SettingsWindowController!
    private var onboardingController: OnboardingWindowController!
    private var shortcutMenuItems: [HotkeySlot: NSMenuItem] = [:]

    private var panelHotkeyDisplay: String { hotkeyConfigs[.panel]!.displayString }

    private static let didOnboardKey = "ClipFlow.didOnboard"

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = PanelController(store: store) { [weak self] item in
            self?.paste(item)
        }

        setupStatusItem()

        monitor.onCapture = { [weak self] capture in
            switch capture {
            case .text(let string): self?.store.addText(string)
            case .image(let data): self?.store.addImage(data)
            }
        }
        monitor.start()

        // Kopyalanan görüntü için changeCount senkronlanmaz: izleyici onu
        // normal yoldan yakalayıp geçmişe ekler.
        captureController.onPermissionNeeded = { [weak self] in
            self?.openOnboarding()
        }

        hotkey.setHandler(for: .panel) { [weak self] in
            self?.panelController.toggle()
        }
        hotkey.setHandler(for: .capture) { [weak self] in
            self?.captureController.start()
        }
        for slot in HotkeySlot.allCases {
            hotkey.register(hotkeyConfigs[slot]!, for: slot)
        }

        setupSettings()
        onboardingController = OnboardingWindowController(
            model: OnboardingModel(hotkeyDisplay: panelHotkeyDisplay)
        )

        // İlk açılışta sistem diyaloğunu doğrudan fırlatmak yerine, izni
        // bağlamıyla anlatan tanıtım ekranını göster (App Review beklentisi).
        // İzin yine de isteğe bağlıdır; sonradan ilk yapıştırma denemesinde
        // veya menüdeki "Hoş Geldiniz…" üzerinden de verilebilir.
        if !UserDefaults.standard.bool(forKey: Self.didOnboardKey) {
            UserDefaults.standard.set(true, forKey: Self.didOnboardKey)
            onboardingController.show(hotkeyDisplay: panelHotkeyDisplay)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotkey.unregister()
    }

    // MARK: - Ayarlar (kısayol seçimi)

    private func setupSettings() {
        settingsModels = HotkeySlot.allCases.map { slot in
            let model = HotkeySettingsModel(slot: slot, current: hotkeyConfigs[slot]!)

            // Yeni kısayolu dene; başarısızsa eskisine geri dön.
            model.applyConfig = { [weak self] config in
                guard let self else { return false }
                guard self.hotkey.register(config, for: slot) else {
                    self.hotkey.register(self.hotkeyConfigs[slot]!, for: slot)
                    return false
                }
                self.hotkeyConfigs[slot] = config
                config.save(slot)
                self.updateMenuShortcut(for: slot)
                return true
            }

            model.isUsedElsewhere = { [weak self] config in
                guard let self else { return false }
                return HotkeySlot.allCases.contains { $0 != slot && self.hotkeyConfigs[$0] == config }
            }

            // Kayıt sırasında mevcut kısayollar tetiklenmesin diye duraklat.
            model.onRecordingStateChange = { [weak self] isRecording in
                guard let self else { return }
                if isRecording {
                    self.hotkey.pauseAll()
                } else if !self.settingsModels.contains(where: { $0.isRecording }) {
                    for slot in HotkeySlot.allCases {
                        self.hotkey.register(self.hotkeyConfigs[slot]!, for: slot)
                    }
                }
            }
            return model
        }

        settingsController = SettingsWindowController(models: settingsModels)
    }

    private func updateMenuShortcut(for slot: HotkeySlot) {
        guard let item = shortcutMenuItems[slot], let config = hotkeyConfigs[slot] else { return }
        item.keyEquivalent = config.menuKeyEquivalent
        item.keyEquivalentModifierMask = config.cocoaModifiers
    }

    // MARK: - Yapıştırma akışı

    private func paste(_ item: ClipboardItem) {
        store.copyToPasteboard(item)
        // Kendi yazdığımızı geçmişe tekrar eklememek için sayacı senkronla.
        monitor.syncChangeCount()
        Paster.sendCmdV()
    }

    // MARK: - Menü çubuğu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipFlow"
        )

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Panoyu Aç", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        shortcutMenuItems[.panel] = openItem

        let captureItem = NSMenuItem(title: "Ekran Görüntüsü Al", action: #selector(startCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        shortcutMenuItems[.capture] = captureItem

        HotkeySlot.allCases.forEach(updateMenuShortcut)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "Sabitlenmemişleri Temizle",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        let settingsItem = NSMenuItem(
            title: "Ayarlar…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let welcomeItem = NSMenuItem(
            title: "Hoş Geldiniz…",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        menu.addItem(welcomeItem)

        let loginItem = NSMenuItem(
            title: "Girişte Başlat",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "ClipFlow'dan Çık",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func startCapture() {
        // Menü kapanıp ekrandan silinsin, sonra yakala.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.captureController.start()
        }
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func openOnboarding() {
        onboardingController.show(hotkeyDisplay: panelHotkeyDisplay)
    }

    @objc private func clearHistory() {
        store.clearUnpinned()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            NSLog("Girişte başlatma ayarı değiştirilemedi: \(error)")
        }
    }
}
