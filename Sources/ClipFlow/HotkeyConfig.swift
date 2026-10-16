import AppKit
import Carbon.HIToolbox

/// Uygulamanın global kısayol yuvaları. `rawValue`, Carbon kısayol kimliğidir.
enum HotkeySlot: UInt32, CaseIterable {
    case panel = 1
    case capture = 2

    var defaultConfig: HotkeyConfig {
        switch self {
        case .panel: return HotkeyConfig(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .capture: return HotkeyConfig(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey | shiftKey))
        }
    }

    /// `panel` eski anahtarı korur — mevcut kurulumların ayarı kaybolmaz.
    fileprivate var defaultsKey: String {
        switch self {
        case .panel: return "ClipFlow.hotkey"
        case .capture: return "ClipFlow.captureHotkey"
        }
    }

    var title: String {
        switch self {
        case .panel: return "Panoyu Açma Kısayolu"
        case .capture: return "Ekran Görüntüsü Kısayolu"
        }
    }
}

/// Kullanıcının seçtiği global kısayol; UserDefaults'ta JSON olarak saklanır.
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static func load(_ slot: HotkeySlot) -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: slot.defaultsKey),
              let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return slot.defaultConfig
        }
        return config
    }

    func save(_ slot: HotkeySlot) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: slot.defaultsKey)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Klavye olayından kısayol üretir. Yanlışlıkla tetiklemeyi önlemek için
    /// en az bir "güçlü" modifier (⌘, ⌥ veya ⌃) zorunludur.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
    }

    /// Örn. "⌃⌥⇧⌘V" — macOS'un standart modifier sıralamasıyla.
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + KeyCodeTranslator.string(for: keyCode)
    }

    /// Menü ögesindeki kısayol göstergesi için.
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// NSMenuItem yalnızca basit karakterleri keyEquivalent olarak kabul eder;
    /// F-tuşları/ok tuşları gibi özel tuşlarda boş bırakılır.
    var menuKeyEquivalent: String {
        let string = KeyCodeTranslator.string(for: keyCode)
        guard string.count == 1, let scalar = string.unicodeScalars.first, scalar.isASCII else {
            return ""
        }
        return string.lowercased()
    }
}

/// Sanal tuş kodunu kullanıcının görebileceği bir metne çevirir.
/// Harf/rakam tuşları aktif klavye düzenine göre (UCKeyTranslate) çözülür,
/// özel tuşlar sabit tablodan gelir.
enum KeyCodeTranslator {
    private static let specialKeys: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Boşluk", 51: "⌫", 53: "⎋", 76: "⌅",
        115: "↖", 117: "⌦", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func string(for keyCode: UInt32) -> String {
        if let special = specialKeys[keyCode] { return special }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { buffer -> String in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return "?"
            }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let error = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0, // modifier'sız temel karakter
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard error == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }
    }
}
