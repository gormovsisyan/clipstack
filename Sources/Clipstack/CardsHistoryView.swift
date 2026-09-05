import AppKit
import SwiftUI

/// Experimental "Cards" theme: near-solid backdrop, each entry as a bordered card with a kind
/// chip, key caps for shortcuts, and wider image previews. Toggle with ⌘T or the menu.
struct CardsHistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var state: PanelState
    let items: [ClipItem]
    let searchFocused: FocusState<Bool>.Binding
    let onPaste: (ClipItem) -> Void
    let onCopyOnly: (ClipItem) -> Void
    let onEnableAccessibility: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if !state.accessibilityTrusted {
                AccessibilityBanner(onEnable: onEnableAccessibility)
            }
            if items.isEmpty {
                EmptyStateView(searching: !state.searchText.isEmpty)
            } else {
                ItemListView(store: store, state: state, items: items, spacing: 8, padding: 12,
                             onPaste: onPaste, onCopyOnly: onCopyOnly) { item, index, isSelected in
                    CardRow(store: store, item: item, index: index, isSelected: isSelected,
                            onPin: { store.togglePin(item.id) },
                            onDelete: { store.remove(item.id) })
                }
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(searchFocused)
                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.1)))

            Text("\(items.count)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.1)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "Paste")
            hint("⌘⌫", "Delete")
            hint("⌘P", "Pin")
            hint("⌘T", "Style")
            Spacer()
            if store.items.contains(where: { !$0.pinned }) {
                Button("Clear") { store.clear(keepPinned: true) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().stroke(Color.primary.opacity(0.14)))
                    .help("Remove all unpinned items")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider() }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(key)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CardRow: View {
    @ObservedObject var store: HistoryStore
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let onPin: () -> Void
    let onDelete: () -> Void

    private static let maxThumbnail = CGSize(width: 308, height: 130)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                icon
                    .frame(width: 16, height: 16)
                Text(item.kind.label.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(kindColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(kindColor.opacity(0.13)))
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                if isSelected {
                    HStack(spacing: 8) {
                        Button(action: onPin) {
                            Image(systemName: item.pinned ? "pin.slash" : "pin")
                        }
                        .help(item.pinned ? "Unpin" : "Pin")
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .help("Delete")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                if index < 9 {
                    KeyCap("⌘\(index + 1)")
                }
            }
            content
            Text(item.date, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
    }

    private var kindColor: Color {
        switch item.kind {
        case .text: return .blue
        case .image: return .purple
        case .files: return .teal
        }
    }

    @ViewBuilder private var icon: some View {
        if let appIcon = store.appIcon(for: item.sourceBundleID) {
            Image(nsImage: appIcon).resizable()
        } else {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(item.previewText)
                .font(.system(size: 13))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .image:
            if let thumbnail = store.thumbnail(for: item) {
                let size = item.thumbnailSize(fitting: Self.maxThumbnail)
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
            } else {
                Text("Image unavailable")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .files:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(item.fileNames.prefix(3), id: \.self) { name in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                }
                if item.fileNames.count > 3 {
                    Text("and \(item.fileNames.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small keyboard-key badge, like the key caps on the website.
struct KeyCap: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.14)))
    }
}
