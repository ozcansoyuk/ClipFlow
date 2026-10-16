import AppKit

/// Bir ekranı tamamen kaplayan, menü çubuğu ve tam ekran uygulamaların
/// da üstünde duran kenarlıksız pencere.
final class CaptureOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Ekran görüntüsü akışı: tüm ekranları dondur, her ekrana bir overlay aç,
/// seçim + işaretleme sonucunu panoya kopyala, overlay'leri kapat.
final class CaptureController {
    /// Ekran Kaydı izni yoksa çağrılır (izin tanıtım ekranını açmak için).
    var onPermissionNeeded: (() -> Void)?

    private let settings = AnnotationSettings()
    private var overlays: [CaptureOverlayWindow] = []
    private var canvases: [CaptureCanvasView] = []
    private var isCapturing = false
    private var previousApp: NSRunningApplication?

    func start() {
        guard !isCapturing else { return }
        guard ScreenCapturer.hasPermission else {
            ScreenCapturer.requestPermission()
            onPermissionNeeded?()
            return
        }
        isCapturing = true
        previousApp = NSWorkspace.shared.frontmostApplication

        Task { @MainActor in
            do {
                let images = try await ScreenCapturer.captureAllDisplays()
                present(images)
            } catch {
                NSLog("Ekran görüntüsü alınamadı: \(error)")
                isCapturing = false
                onPermissionNeeded?()
            }
        }
    }

    private func present(_ images: [CGDirectDisplayID: CGImage]) {
        settings.tool = nil

        for screen in NSScreen.screens {
            guard let id = screen.displayID, let image = images[id] else { continue }
            let window = CaptureOverlayWindow(screen: screen)
            let canvas = CaptureCanvasView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                image: image,
                settings: settings
            )
            canvas.canBeginSelection = { [weak self] canvas in
                // Başka ekranda işaretleme varsa yeni seçimle silinmesin.
                !(self?.canvases.contains { $0 !== canvas && $0.hasAnnotations } ?? false)
            }
            canvas.onSelectionBegan = { [weak self] canvas in
                self?.canvases.filter { $0 !== canvas }.forEach { $0.clearSelection() }
            }
            canvas.onCopy = { [weak self] canvas in self?.copy(from: canvas) }
            canvas.onCancel = { [weak self] in self?.finish() }

            window.contentView = canvas
            overlays.append(window)
            canvases.append(canvas)
        }

        guard !overlays.isEmpty else {
            isCapturing = false
            return
        }

        NSApp.activate()
        // Klavye odağı imlecin bulunduğu ekranda olsun (↩ = o ekranın tamamı).
        let mouse = NSEvent.mouseLocation
        let keyIndex = overlays.firstIndex { $0.frame.contains(mouse) } ?? 0
        for (index, window) in overlays.enumerated() where index != keyIndex {
            window.orderFrontRegardless()
        }
        overlays[keyIndex].makeKeyAndOrderFront(nil)
        canvases[keyIndex].focusCanvas()
    }

    private func copy(from canvas: CaptureCanvasView) {
        guard let selection = canvas.selection,
              let image = CaptureExporter.render(
                image: canvas.image,
                viewSize: canvas.bounds.size,
                selection: selection,
                annotations: canvas.annotations
              ) else {
            NSSound.beep()
            return
        }
        CaptureExporter.copyToPasteboard(image, pointSize: selection.size)
        finish()
    }

    private func finish() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.forEach { $0.close() }
        overlays = []
        canvases = []
        isCapturing = false
        previousApp?.activate()
        previousApp = nil
    }
}
