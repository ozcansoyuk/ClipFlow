import AppKit
import Carbon.HIToolbox

/// Kullanıcının seçtiği global kısayolları sistem genelinde kaydeder.
///
/// Carbon `RegisterEventHotKey` kullanılır: olay tabanlıdır (polling yok),
/// Accessibility izni GEREKTİRMEZ ve onlarca yıldır en stabil global
/// kısayol API'sidir (Raycast, Alfred vb. de aynısını kullanır).
///
/// Tek yönetici birden çok kısayolu (slot) taşır; olay işleyici basılan
/// kısayolun kimliğini okuyup yalnızca ilgili slotun işleyicisini çağırır.
final class HotkeyManager {
    private var hotKeyRefs: [HotkeySlot: EventHotKeyRef] = [:]
    private var handlers: [HotkeySlot: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private static let signature = OSType(0x434C_4657) // 'CLFW'

    func setHandler(for slot: HotkeySlot, _ handler: @escaping () -> Void) {
        handlers[slot] = handler
    }

    /// Verilen kısayolu slota kaydeder; slotun öncekini varsa kaldırır.
    /// Kısayol sistem/başka uygulama tarafından alınmışsa `false` döner.
    @discardableResult
    func register(_ config: HotkeyConfig, for slot: HotkeySlot) -> Bool {
        installHandlerIfNeeded()
        pause(slot)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRefs[slot] = ref
        return true
    }

    /// Slotun kısayolunu geçici olarak devre dışı bırakır.
    func pause(_ slot: HotkeySlot) {
        if let ref = hotKeyRefs.removeValue(forKey: slot) {
            UnregisterEventHotKey(ref)
        }
    }

    /// Kısayol kaydedici açıkken kullanıcının mevcut kombinasyonlardan birine
    /// basması paneli/yakalamayı tetiklememeli.
    func pauseAll() {
        HotkeySlot.allCases.forEach(pause)
    }

    func unregister() {
        pauseAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == HotkeyManager.signature,
                  let slot = HotkeySlot(rawValue: hotKeyID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.handlers[slot]?()
            }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit { unregister() }
}
