import AppKit

/// Ekran görüntüsü üzerindeki işaretleme araçları.
enum AnnotationTool: String, CaseIterable {
    case pen, line, arrow, rectangle, ellipse, text

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        }
    }

    var title: String {
        switch self {
        case .pen: return "Kalem"
        case .line: return "Çizgi"
        case .arrow: return "Ok"
        case .rectangle: return "Dikdörtgen"
        case .ellipse: return "Elips"
        case .text: return "Yazı"
        }
    }

    /// Overlay'de aracı seçen tek harf (modifier'sız).
    var shortcut: String {
        switch self {
        case .pen: return "p"
        case .line: return "l"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .text: return "t"
        }
    }
}

/// Tek bir işaretleme. Koordinatlar overlay görünümünün nokta (point)
/// uzayındadır; aynı `draw(in:)` hem ekranda hem dışa aktarmada kullanılır,
/// böylece panoya giden görüntü ekrandakiyle birebir aynıdır.
struct Annotation {
    enum Shape {
        case pen([CGPoint])
        case line(CGPoint, CGPoint)
        case arrow(CGPoint, CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        /// Metin ve kutusunun sol üst köşesi.
        case text(String, CGPoint)
    }

    var shape: Shape
    var color: NSColor
    var lineWidth: CGFloat

    /// Yazı boyutu kalınlıkla birlikte büyür: 2 → 16, 4 → 24, 8 → 40 pt.
    static func fontSize(for lineWidth: CGFloat) -> CGFloat {
        lineWidth * 4 + 8
    }

    static func font(for lineWidth: CGFloat) -> NSFont {
        .systemFont(ofSize: fontSize(for: lineWidth), weight: .semibold)
    }

    /// Çizilecek bir şey yoksa (tek tıklama gibi) `false`.
    var isMeaningful: Bool {
        switch shape {
        case .pen(let points): return points.count > 1
        case .line(let a, let b), .arrow(let a, let b): return hypot(b.x - a.x, b.y - a.y) > 2
        case .rectangle(let rect), .ellipse(let rect): return rect.width > 2 || rect.height > 2
        case .text(let string, _): return !string.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Yazı işaretlemesinin kapladığı kutu (tutup sürüklemek için); diğer
    /// şekillerde `nil`.
    var textBounds: CGRect? {
        guard case .text(let string, let topLeft) = shape else { return nil }
        let size = Self.attributedText(string, color: color, lineWidth: lineWidth).size()
        return CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }

    func draw(in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch shape {
        case .pen(let points):
            guard let first = points.first else { return }
            ctx.move(to: first)
            points.dropFirst().forEach { ctx.addLine(to: $0) }
            ctx.strokePath()

        case .line(let a, let b):
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()

        case .arrow(let a, let b):
            drawArrow(from: a, to: b, in: ctx)

        case .rectangle(let rect):
            ctx.stroke(rect)

        case .ellipse(let rect):
            ctx.strokeEllipse(in: rect)

        case .text(let string, let topLeft):
            let attributed = Self.attributedText(string, color: color, lineWidth: lineWidth)
            let size = attributed.size()
            let rect = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            attributed.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func attributedText(_ string: String, color: NSColor, lineWidth: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: font(for: lineWidth),
            .foregroundColor: color,
        ])
    }

    /// Gövde, ok ucunun tabanında biter; uç dolu bir üçgendir.
    private func drawArrow(from a: CGPoint, to b: CGPoint, in ctx: CGContext) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let length = hypot(b.x - a.x, b.y - a.y)
        let headLength = min(max(12, lineWidth * 4), length)
        let spread = CGFloat.pi / 7

        let base = CGPoint(
            x: b.x - cos(angle) * headLength * 0.8,
            y: b.y - sin(angle) * headLength * 0.8
        )
        ctx.move(to: a)
        ctx.addLine(to: base)
        ctx.strokePath()

        ctx.move(to: b)
        ctx.addLine(to: CGPoint(
            x: b.x - cos(angle - spread) * headLength,
            y: b.y - sin(angle - spread) * headLength
        ))
        ctx.addLine(to: CGPoint(
            x: b.x - cos(angle + spread) * headLength,
            y: b.y - sin(angle + spread) * headLength
        ))
        ctx.closePath()
        ctx.fillPath()
    }
}

// MARK: - ⇧ kilidi

enum ShapeConstraint {
    /// Çizgi/ok: açıyı 45°'nin katlarına yuvarlar.
    static func snapAngle(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }

    /// Dikdörtgen/elips: iki köşeden kare kutu üretir (sürükleme yönü korunur).
    static func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: a.x, y: a.y, width: dx, height: dy).standardized
    }
}
