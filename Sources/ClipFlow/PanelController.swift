import AppKit
import SwiftUI

/// Klavyeyle gezinilen seçimin durumu — SwiftUI görünümü bunu gözlemler.
final class SelectionState: ObservableObject {
    @Published var index: Int = 0
}

/// Paneli yönetir: imleç konumunda gösterme, klavye navigasyonu ve seçim.
final class PanelController {
    private let panel: ClipboardPanel
    private let store: ClipboardStore
    private let selection = SelectionState()
    private let onPaste: (ClipboardItem) -> Void
    private var keyMonitor: Any?

    private static let panelSize = NSSize(width: 360, height: 440)

    init(store: ClipboardStore, onPaste: @escaping (ClipboardItem) -> Void) {
        self.store = store
        self.onPaste = onPaste
        self.panel = ClipboardPanel(size: Self.panelSize)

        let rootView = ClipboardListView(
            store: store,
            selection: selection,
            onChoose: { [weak self] item in self?.choose(item) },
            onTogglePin: { [weak self] item in
                store.togglePin(item)
                self?.clampSelection()
            },
            onDelete: { [weak self] item in
                store.remove(item)
                self?.clampSelection()
            },
            onClear: { [weak self] in
                store.clearUnpinned()
                self?.clampSelection()
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        panel.onResignKey = { [weak self] in self?.hide() }
    }

    // MARK: - Görünürlük

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    /// Paneli imlecin bulunduğu noktada açar (Win+V davranışı).
    func show() {
        selection.index = 0
        positionAtMouse()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func positionAtMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // Panelin sol üst köşesi imlece gelsin; ekran dışına taşarsa içeri it.
        var origin = NSPoint(x: mouse.x + 4, y: mouse.y - Self.panelSize.height - 4)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.panelSize.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - Self.panelSize.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Klavye navigasyonu

    /// Olaylar SwiftUI hiyerarşisine ulaşmadan önce yakalanır; böylece ok
    /// tuşlarını ScrollView'un tüketmesi engellenir.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let count = store.items.count

        switch event.keyCode {
        case 126: // Yukarı ok
            guard count > 0 else { return true }
            selection.index = max(0, selection.index - 1)
            return true
        case 125: // Aşağı ok
            guard count > 0 else { return true }
            selection.index = min(count - 1, selection.index + 1)
            return true
        case 36, 76: // Return / Enter
            if let item = store.items[safe: selection.index] {
                choose(item)
            }
            return true
        case 53: // Escape
            hide()
            return true
        default:
            // 1-9 sayı tuşlarıyla hızlı seçim (modifier'sız).
            if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
               let characters = event.charactersIgnoringModifiers,
               let digit = Int(characters),
               (1...9).contains(digit),
               let item = store.items[safe: digit - 1] {
                choose(item)
                return true
            }
            return false
        }
    }

    // MARK: - Seçim

    private func choose(_ item: ClipboardItem) {
        hide()
        onPaste(item)
    }

    private func clampSelection() {
        selection.index = max(0, min(selection.index, store.items.count - 1))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
