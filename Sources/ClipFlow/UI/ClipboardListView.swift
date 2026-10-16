import SwiftUI

/// Panelin SwiftUI içeriği: başlık, sabitlenmiş/geçmiş bölümleri, kısayol ipuçları.
struct ClipboardListView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var selection: SelectionState

    let onChoose: (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if store.items.isEmpty {
                emptyState
            } else {
                list
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 360, height: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Başlık

    private var header: some View {
        HStack {
            Label("Pano Geçmişi", systemImage: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Sabitlenmemiş geçmişi temizle")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Liste

    private var pinnedCount: Int {
        store.items.prefix(while: \.isPinned).count
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        if index == 0 && item.isPinned {
                            sectionLabel("SABİTLENMİŞ")
                        }
                        if index == pinnedCount && pinnedCount > 0 {
                            sectionLabel("GEÇMİŞ")
                        }
                        ClipboardRow(
                            item: item,
                            index: index,
                            isSelected: index == selection.index,
                            thumbnail: store.thumbnail(for: item),
                            onChoose: { onChoose(item) },
                            onTogglePin: { onTogglePin(item) },
                            onDelete: { onDelete(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selection.index) { _, newIndex in
                if let item = store.items[safe: newIndex] {
                    proxy.scrollTo(item.id)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    // MARK: - Boş durum

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Henüz kopyalanan bir şey yok")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Kopyaladığınız metin ve resimler burada görünecek")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Alt bilgi

    private var footer: some View {
        HStack(spacing: 12) {
            hint(key: "↑↓", label: "Gezin")
            hint(key: "⏎", label: "Yapıştır")
            hint(key: "1–9", label: "Hızlı Seç")
            hint(key: "esc", label: "Kapat")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func hint(key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Satır görünümü

private struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let thumbnail: NSImage?
    let onChoose: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            indexBadge
            content
            actions
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.22)
                        : (isHovering ? Color.primary.opacity(0.06) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onChoose)
        .onHover { isHovering = $0 }
        .help(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
    }

    private var indexBadge: some View {
        Text(index < 9 ? "\(index + 1)" : "·")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .frame(width: 17, height: 17)
            .background(
                Circle().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
            )
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(item.previewText)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 56)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Label("Resim", systemImage: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.isPinned ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .opacity(item.isPinned || isHovering ? 1 : 0.25)
            .help(item.isPinned ? "Sabitlemeyi kaldır" : "Sabitle")

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Sil")
        }
    }
}
