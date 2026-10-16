import AppKit
import SwiftUI

/// Tüm overlay'lerin paylaştığı araç/renk/kalınlık seçimi. Renk ve kalınlık
/// oturumlar arasında hatırlanır; araç Lightshot'taki gibi her yakalamada
/// boş başlar (araçsız sürükleme seçimi taşır).
final class AnnotationSettings: ObservableObject {
    static let palette: [NSColor] = [
        NSColor(srgbRed: 0.94, green: 0.20, blue: 0.20, alpha: 1), // kırmızı
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1), // turuncu
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.00, alpha: 1), // sarı
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), // yeşil
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), // mavi
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1), // mor
        NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1), // siyah
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1), // beyaz
    ]
    static let widths: [CGFloat] = [2, 4, 8]

    private static let colorKey = "ClipFlow.capture.colorIndex"
    private static let widthKey = "ClipFlow.capture.lineWidth"

    @Published var tool: AnnotationTool?
    @Published var colorIndex: Int {
        didSet { UserDefaults.standard.set(colorIndex, forKey: Self.colorKey) }
    }
    @Published var lineWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(lineWidth), forKey: Self.widthKey) }
    }

    var color: NSColor { Self.palette[colorIndex] }

    init() {
        let defaults = UserDefaults.standard
        let index = defaults.integer(forKey: Self.colorKey)
        colorIndex = Self.palette.indices.contains(index) ? index : 0
        let width = CGFloat(defaults.double(forKey: Self.widthKey))
        lineWidth = Self.widths.contains(width) ? width : 4
    }

    /// Aynı araca tekrar basmak aracı bırakır (taşıma moduna döner).
    func toggle(_ tool: AnnotationTool) {
        self.tool = self.tool == tool ? nil : tool
    }
}

/// Bir overlay'in araç çubuklarına bağladığı eylemler ve geri al durumu.
final class CaptureToolbarModel: ObservableObject {
    @Published var canUndo = false
    var onUndo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?
    /// Bir düğmeye basıldıktan sonra klavye odağını tuvale geri vermek için.
    var onInteraction: (() -> Void)?
}

// MARK: - Dikey araç çubuğu (seçimin sağında)

struct ToolsBar: View {
    @ObservedObject var settings: AnnotationSettings
    @ObservedObject var model: CaptureToolbarModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                ToolbarIconButton(
                    symbol: tool.symbol,
                    help: "\(tool.title) (\(tool.shortcut.uppercased()))",
                    isActive: settings.tool == tool
                ) {
                    settings.toggle(tool)
                    model.onInteraction?()
                }
            }
            Divider().frame(width: 22).padding(.vertical, 3)
            ToolbarIconButton(symbol: "arrow.uturn.backward", help: "Geri Al (⌘Z)", isActive: false) {
                model.onUndo?()
            }
            .disabled(!model.canUndo)
        }
        .padding(4)
        .background(ToolbarBackground())
    }
}

// MARK: - Yatay eylem çubuğu (seçimin altında)

struct ActionsBar: View {
    @ObservedObject var settings: AnnotationSettings
    @ObservedObject var model: CaptureToolbarModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationSettings.palette.indices, id: \.self) { index in
                Button {
                    settings.colorIndex = index
                    model.onInteraction?()
                } label: {
                    Circle()
                        .fill(Color(nsColor: AnnotationSettings.palette[index]))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(
                                settings.colorIndex == index ? Color.accentColor : .clear,
                                lineWidth: 2
                            )
                        )
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 20)

            ForEach(AnnotationSettings.widths, id: \.self) { width in
                Button {
                    settings.lineWidth = width
                    model.onInteraction?()
                } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: width + 3, height: width + 3)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(settings.lineWidth == width ? Color.accentColor.opacity(0.25) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Kalınlık \(Int(width))")
            }

            Divider().frame(height: 20)

            ToolbarIconButton(symbol: "doc.on.doc", help: "Panoya Kopyala (⌘C / ↩)", isActive: false) {
                model.onCopy?()
            }
            ToolbarIconButton(symbol: "xmark", help: "Kapat (⎋)", isActive: false) {
                model.onClose?()
            }
        }
        .padding(4)
        .background(ToolbarBackground())
    }
}

// MARK: - Ortak parçalar

private struct ToolbarIconButton: View {
    let symbol: String
    let help: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ToolbarBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}
