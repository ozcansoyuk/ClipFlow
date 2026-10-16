import AppKit
import Combine
import SwiftUI

/// Bir ekranı kaplayan yakalama tuvali: donmuş görüntüyü karartarak çizer,
/// bölge seçimini (oluşturma/taşıma/yeniden boyutlandırma) ve seçimin içine
/// işaretleme yapmayı yönetir. Koordinatlar sol alt kökenli nokta uzayıdır.
final class CaptureCanvasView: NSView, NSTextFieldDelegate {
    // MARK: Denetleyiciye açılan arayüz

    /// Yeni bir seçime başlamadan önce sorulur (başka ekranda işaretleme
    /// varsa onu kaybetmemek için reddedilebilir).
    var canBeginSelection: ((CaptureCanvasView) -> Bool)?
    var onSelectionBegan: ((CaptureCanvasView) -> Void)?
    var onCopy: ((CaptureCanvasView) -> Void)?
    var onCancel: (() -> Void)?

    let image: CGImage
    private(set) var selection: CGRect?
    private(set) var annotations: [Annotation] = []
    /// Her değişiklikten önceki işaretleme listesi — ⌘Z ekleme kadar yazı
    /// taşımayı da geri alır.
    private var undoStack: [[Annotation]] = [] {
        didSet { toolbarModel.canUndo = !undoStack.isEmpty }
    }
    var hasAnnotations: Bool { !annotations.isEmpty }

    // MARK: İç durum

    private enum Handle: CaseIterable {
        case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left
    }

    private enum DragMode {
        case none
        case creatingSelection(start: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(Handle, original: CGRect)
        case drawing(start: CGPoint)
        case movingText(index: Int, start: CGPoint, original: CGPoint)
    }

    private let settings: AnnotationSettings
    private let toolbarModel = CaptureToolbarModel()
    private var toolsBar: NSHostingView<ToolsBar>!
    private var actionsBar: NSHostingView<ActionsBar>!
    private var dragMode: DragMode = .none
    private var draft: Annotation?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var textLineWidth: CGFloat = 4
    /// Çift tıklamayla düzenlenen yazı: düzenleme sürerken listeden çıkarılır,
    /// bitince aynı sıraya geri konur (üst üste binme sırası değişmez).
    private var editingText: (index: Int, original: Annotation)?
    private var trackingArea: NSTrackingArea?
    /// İmlecin üzerinde durduğu yazı; çerçevesi gösterilir.
    private var hoveredText: Int?
    private var cancellables: Set<AnyCancellable> = []

    private static let dimAlpha: CGFloat = 0.45
    private static let handleSize: CGFloat = 8
    private static let minSelection: CGFloat = 4
    private static let textFramePadding: CGFloat = 4

    init(frame: NSRect, image: CGImage, settings: AnnotationSettings) {
        self.image = image
        self.settings = settings
        super.init(frame: frame)

        toolbarModel.onUndo = { [weak self] in self?.undo() }
        toolbarModel.onCopy = { [weak self] in self?.copySelection() }
        toolbarModel.onClose = { [weak self] in self?.onCancel?() }
        toolbarModel.onInteraction = { [weak self] in self?.focusCanvas() }

        toolsBar = NSHostingView(rootView: ToolsBar(settings: settings, model: toolbarModel))
        actionsBar = NSHostingView(rootView: ActionsBar(settings: settings, model: toolbarModel))
        for bar in [toolsBar!, actionsBar!] as [NSView] {
            bar.isHidden = true
            addSubview(bar)
        }

        // Araç değişince açık yazı kutusunu kaydet, imleci güncelle.
        settings.$tool
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.commitText()
                    self.window?.invalidateCursorRects(for: self)
                }
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Dış komutlar

    /// Başka ekranda yeni seçim başlayınca bu ekrandaki seçim kalkar.
    func clearSelection() {
        commitText()
        selection = nil
        annotations = []
        undoStack = []
        hoveredText = nil
        dragMode = .none
        updateToolbars()
        needsDisplay = true
    }

    func focusCanvas() {
        window?.makeFirstResponder(self)
    }

    /// Seçim yoksa ekranın tamamı kopyalanır.
    func copySelection() {
        commitText()
        if selection == nil {
            selection = bounds
        }
        onCopy?(self)
    }

    func undo() {
        if textField != nil {
            cancelText()
            return
        }
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
        hoveredText = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func recordUndo() {
        undoStack.append(annotations)
    }

    // MARK: - Çizim

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: bounds)

        // Seçim dışını karart.
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(Self.dimAlpha).cgColor)
        if let selection {
            ctx.addRect(bounds)
            ctx.addRect(selection)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }
        ctx.restoreGState()

        guard let selection else {
            drawHint()
            return
        }

        // İşaretlemeler yalnızca seçimin içinde görünür.
        ctx.saveGState()
        ctx.clip(to: selection)
        annotations.forEach { $0.draw(in: ctx) }
        draft?.draw(in: ctx)
        ctx.restoreGState()

        // Üzerinde durulan / sürüklenen yazının çerçevesi.
        if let frame = activeTextIndex.flatMap({ annotations[safe: $0]?.textBounds }) {
            ctx.saveGState()
            let rect = frame.insetBy(dx: -Self.textFramePadding, dy: -Self.textFramePadding)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(rect)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(rect)
            ctx.restoreGState()
        }

        // Seçim çerçevesi ve tutamaçlar.
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
        ctx.restoreGState()

        if !isCreatingSelection {
            for handle in Handle.allCases {
                let rect = handleRect(handle, in: selection)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            }
        }

        drawSizeLabel(for: selection)
    }

    private var isCreatingSelection: Bool {
        if case .creatingSelection = dragMode { return true }
        return false
    }

    private var backingScale: CGFloat {
        CGFloat(image.width) / max(bounds.width, 1)
    }

    /// Seçimin üstünde piksel cinsinden "1280 × 720" etiketi.
    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int((selection.width * backingScale).rounded())) × \(Int((selection.height * backingScale).rounded()))"
        drawPill(text, fontSize: 11) { size in
            var origin = CGPoint(x: selection.minX, y: selection.maxY + 6)
            if origin.y + size.height > bounds.maxY - 2 {
                origin.y = selection.maxY - size.height - 6 // üstte yer yoksa içeri al
                origin.x += 6
            }
            origin.x = min(max(origin.x, bounds.minX + 2), bounds.maxX - size.width - 2)
            return origin
        }
    }

    private func drawHint() {
        let text = "Bölge seçmek için sürükleyin  ·  ↩ tüm ekran  ·  ⎋ iptal"
        drawPill(text, fontSize: 13) { size in
            CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        }
    }

    private func drawPill(_ text: String, fontSize: CGFloat, origin: (CGSize) -> CGPoint) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let textSize = attributed.size()
        let padding = CGSize(width: 8, height: 4)
        let size = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        let rect = CGRect(origin: origin(size), size: size)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        attributed.draw(at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height))
    }

    // MARK: - Tutamaçlar

    private func handlePoint(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handleRect(_ handle: Handle, in rect: CGRect) -> CGRect {
        let p = handlePoint(handle, in: rect)
        let s = Self.handleSize
        return CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
    }

    private func handle(at point: CGPoint) -> Handle? {
        guard let selection else { return nil }
        return Handle.allCases.first { handleRect($0, in: selection).insetBy(dx: -4, dy: -4).contains(point) }
    }

    private func resized(_ rect: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .bottomLeft: minX = p.x; minY = p.y
        case .bottom: minY = p.y
        case .bottomRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .topRight: maxX = p.x; maxY = p.y
        case .top: maxY = p.y
        case .topLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    }

    /// Seçimi tam noktalara oturt ve ekran sınırına kırp.
    private func normalized(_ rect: CGRect) -> CGRect {
        let r = CGRect(
            x: rect.minX.rounded(), y: rect.minY.rounded(),
            width: rect.width.rounded(), height: rect.height.rounded()
        )
        return r.intersection(bounds)
    }

    // MARK: - Fare

    override func mouseDown(with event: NSEvent) {
        let p = clamped(convert(event.locationInWindow, from: nil))
        window?.makeKeyAndOrderFront(nil)
        focusCanvas()

        let wasEditingText = textField != nil
        commitText()

        if let selection {
            if let handle = handle(at: p) {
                dragMode = .resizing(handle, original: selection)
                return
            }
            if selection.contains(p) {
                // Çift tıklama: yazıyı yeniden düzenle.
                if event.clickCount == 2, let index = textIndex(at: p) {
                    beginEditing(at: index)
                    return
                }
                // Yazıyı çerçevesinden tutup taşı (hangi araç seçili olursa olsun).
                if let index = textIndex(at: p), case .text(_, let origin) = annotations[index].shape {
                    recordUndo()
                    dragMode = .movingText(index: index, start: p, original: origin)
                    NSCursor.closedHand.set()
                    needsDisplay = true
                    return
                }
                switch settings.tool {
                case .none:
                    dragMode = .moving(start: p, original: selection)
                case .text?:
                    if !wasEditingText { beginText(at: p) }
                case .some:
                    dragMode = .drawing(start: p)
                    draft = makeAnnotation(from: p, to: p, shift: false, current: nil)
                }
                return
            }
            // İşaretleme varken dışarı tıklamak işi silmesin.
            guard annotations.isEmpty else { return }
        }

        guard canBeginSelection?(self) ?? true else { return }
        selection = nil
        annotations = []
        undoStack = []
        hoveredText = nil
        dragMode = .creatingSelection(start: p)
        onSelectionBegan?(self)
        updateToolbars()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = clamped(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)

        switch dragMode {
        case .none:
            return
        case .creatingSelection(let start):
            selection = normalized(ShapeConstraint.rect(from: start, to: p, square: shift))
        case .moving(let start, let original):
            var moved = original.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
            selection = normalized(moved)
        case .resizing(let handle, let original):
            selection = normalized(resized(original, handle: handle, to: p))
        case .drawing(let start):
            draft = makeAnnotation(from: start, to: p, shift: shift, current: draft)
        case .movingText(let index, let start, let original):
            guard case .text(let string, _) = annotations[index].shape else { break }
            let origin = CGPoint(x: original.x + p.x - start.x, y: original.y + p.y - start.y)
            annotations[index].shape = .text(string, origin)
        }
        updateToolbars()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .creatingSelection, .resizing:
            if let selection, selection.width < Self.minSelection || selection.height < Self.minSelection {
                self.selection = nil
            }
        case .drawing:
            if let draft, draft.isMeaningful {
                recordUndo()
                annotations.append(draft)
            }
            draft = nil
        case .movingText(let index, _, let original):
            // Hiç kıpırdamadıysa boş geri alma adımı bırakma.
            if case .text(_, let origin) = annotations[index].shape, origin == original {
                undoStack.removeLast()
            }
            hoveredText = index
        case .moving, .none:
            break
        }
        dragMode = .none
        updateToolbars()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: - Yazıyı taşıma

    private var activeTextIndex: Int? {
        if case .movingText(let index, _, _) = dragMode { return index }
        return hoveredText
    }

    /// En üstteki (son eklenen) yazı önce yakalanır.
    private func textIndex(at p: CGPoint) -> Int? {
        annotations.indices.reversed().first { index in
            annotations[index].textBounds?
                .insetBy(dx: -Self.textFramePadding, dy: -Self.textFramePadding)
                .contains(p) ?? false
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let index = selection?.contains(p) == true ? textIndex(at: p) : nil
        if index != hoveredText {
            hoveredText = index
            needsDisplay = true
        }
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    private func makeAnnotation(from a: CGPoint, to b: CGPoint, shift: Bool, current: Annotation?) -> Annotation? {
        guard let tool = settings.tool else { return nil }
        let shape: Annotation.Shape
        switch tool {
        case .pen:
            var points: [CGPoint] = []
            if case .pen(let existing)? = current?.shape { points = existing }
            if points.isEmpty { points.append(a) }
            if points.last != b { points.append(b) }
            shape = .pen(points)
        case .line:
            shape = .line(a, shift ? ShapeConstraint.snapAngle(from: a, to: b) : b)
        case .arrow:
            shape = .arrow(a, shift ? ShapeConstraint.snapAngle(from: a, to: b) : b)
        case .rectangle:
            shape = .rectangle(ShapeConstraint.rect(from: a, to: b, square: shift))
        case .ellipse:
            shape = .ellipse(ShapeConstraint.rect(from: a, to: b, square: shift))
        case .text:
            return nil
        }
        return Annotation(shape: shape, color: settings.color, lineWidth: settings.lineWidth)
    }

    // MARK: - İmleç

    override func resetCursorRects() {
        guard let selection, !isCreatingSelection else {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        addCursorRect(bounds, cursor: annotations.isEmpty ? .crosshair : .arrow)
        let inside: NSCursor
        switch settings.tool {
        case .none: inside = .openHand
        case .text?: inside = .iBeam
        case .some: inside = .crosshair
        }
        addCursorRect(selection, cursor: inside)
        for annotation in annotations {
            if let frame = annotation.textBounds {
                let rect = frame.insetBy(dx: -Self.textFramePadding, dy: -Self.textFramePadding)
                addCursorRect(rect.intersection(selection), cursor: .openHand)
            }
        }
        for handle in Handle.allCases {
            let cursor: NSCursor
            switch handle {
            case .left, .right: cursor = .resizeLeftRight
            case .top, .bottom: cursor = .resizeUpDown
            default: cursor = .crosshair
            }
            addCursorRect(handleRect(handle, in: selection).insetBy(dx: -4, dy: -4), cursor: cursor)
        }
    }

    // MARK: - Araç çubukları

    /// Dikey araç çubuğu seçimin sağında, eylem çubuğu altında; sığmazsa
    /// karşı tarafa, o da olmazsa seçimin içine alınır.
    private func updateToolbars() {
        guard let selection, !isCreatingSelection else {
            toolsBar.isHidden = true
            actionsBar.isHidden = true
            return
        }
        let margin: CGFloat = 8
        let edge: CGFloat = 4

        let toolsSize = toolsBar.fittingSize
        var toolsX = selection.maxX + margin
        if toolsX + toolsSize.width > bounds.maxX - edge {
            toolsX = selection.minX - margin - toolsSize.width
            if toolsX < bounds.minX + edge {
                toolsX = selection.maxX - margin - toolsSize.width
            }
        }
        var toolsY = selection.maxY - toolsSize.height
        toolsY = min(max(toolsY, bounds.minY + edge), bounds.maxY - toolsSize.height - edge)
        toolsBar.frame = CGRect(x: toolsX, y: toolsY, width: toolsSize.width, height: toolsSize.height)

        let actionsSize = actionsBar.fittingSize
        var actionsX = selection.maxX - actionsSize.width
        actionsX = min(max(actionsX, bounds.minX + edge), bounds.maxX - actionsSize.width - edge)
        var actionsY = selection.minY - margin - actionsSize.height
        if actionsY < bounds.minY + edge {
            actionsY = selection.minY + margin
        }
        actionsBar.frame = CGRect(x: actionsX, y: actionsY, width: actionsSize.width, height: actionsSize.height)

        toolsBar.isHidden = false
        actionsBar.isHidden = false
    }

    // MARK: - Yazı aracı

    /// Var olan yazıyı kendi renk/boyutuyla, aynı yerde düzenlemeye açar.
    private func beginEditing(at index: Int) {
        guard case .text(let string, let origin) = annotations[index].shape else { return }
        recordUndo()
        let original = annotations.remove(at: index)
        editingText = (index, original)
        hoveredText = nil
        beginText(at: origin, string: string, color: original.color, lineWidth: original.lineWidth)
        needsDisplay = true
    }

    private func beginText(
        at point: CGPoint,
        string: String = "",
        color: NSColor? = nil,
        lineWidth: CGFloat? = nil
    ) {
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        textLineWidth = lineWidth ?? settings.lineWidth
        field.font = Annotation.font(for: textLineWidth)
        field.textColor = color ?? settings.color
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        textOrigin = point

        addSubview(field)
        textField = field
        layoutTextField()
        window?.makeFirstResponder(field)
        // İmleç metnin sonunda başlasın (tümü seçili değil).
        field.currentEditor()?.selectedRange = NSRange(location: (string as NSString).length, length: 0)
    }

    /// Kutunun sol üst köşesi tıklanan noktada kalır, genişlik metne uyar.
    ///
    /// Düzenleme sürerken hücrenin `stringValue`'su güncellenmez; metin alan
    /// düzenleyicisinden (field editor) okunur. Ölçüm, çizimle aynı fontla
    /// yapılır ve imleç için pay bırakılır — kutu metinden dar kalırsa alan
    /// içeriği sola kaydırır ve baştaki harfler görünmez olur.
    private func layoutTextField() {
        guard let field = textField else { return }
        let editor = field.currentEditor() as? NSTextView
        let string = editor?.string ?? field.stringValue
        let font = Annotation.font(for: textLineWidth)
        let measured = Annotation.attributedText(string.isEmpty ? " " : string, color: .white, lineWidth: textLineWidth).size()
        let height = ceil(max(measured.height, font.ascender - font.descender + font.leading)) + 4
        let width = ceil(measured.width) + font.pointSize + 8
        field.frame = CGRect(x: textOrigin.x - 2, y: textOrigin.y - height, width: width, height: height)
        // Önceden kaymış olabilecek görünümü başa döndür.
        editor?.scrollRangeToVisible(NSRange(location: 0, length: 0))
        editor?.scrollRangeToVisible(editor?.selectedRange() ?? NSRange(location: 0, length: 0))
    }

    func controlTextDidChange(_ obj: Notification) {
        layoutTextField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelText()
            return true
        default:
            return false
        }
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let string = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()

        let annotation = Annotation(
            shape: .text(string, textOrigin),
            color: field.textColor ?? settings.color,
            lineWidth: textLineWidth
        )
        if let editing = editingText {
            editingText = nil
            if !annotation.isMeaningful {
                // Metin silindiyse yazı da silinir; ⌘Z geri getirir.
            } else if case .text(let old, _) = editing.original.shape, old == string {
                annotations.insert(editing.original, at: editing.index)
                undoStack.removeLast() // değişiklik yok
            } else {
                annotations.insert(annotation, at: editing.index)
            }
        } else if annotation.isMeaningful {
            recordUndo()
            annotations.append(annotation)
        }
        window?.invalidateCursorRects(for: self)
        focusCanvas()
        needsDisplay = true
    }

    private func cancelText() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
        // Düzenleme iptal: özgün yazıyı yerine koy.
        if let editing = editingText {
            editingText = nil
            annotations.insert(editing.original, at: editing.index)
            undoStack.removeLast()
        }
        window?.invalidateCursorRects(for: self)
        focusCanvas()
        needsDisplay = true
    }

    // MARK: - Klavye

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard textField == nil else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            copySelection()
            return true
        case "z":
            undo()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Esc
            onCancel?()
            return
        case 36, 76: // Return, Enter
            copySelection()
            return
        default:
            break
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control])
        if flags.isEmpty,
           let key = event.charactersIgnoringModifiers?.lowercased(),
           let tool = AnnotationTool.allCases.first(where: { $0.shortcut == key }) {
            settings.toggle(tool)
            return
        }
        super.keyDown(with: event)
    }
}
