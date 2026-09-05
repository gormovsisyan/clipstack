import AppKit
import SwiftUI

/// UI state shared between the SwiftUI view and the panel controller.
final class PanelState: ObservableObject {
    @Published var searchText = ""
    @Published var selectedID: UUID?
    @Published var accessibilityTrusted = true
    @Published var focusToken = 0
    /// Hover-selection is suppressed briefly after keyboard navigation so the list scrolling
    /// underneath a stationary cursor does not steal the selection.
    var lastKeyboardNavigation: Date = .distantPast

    func filtered(_ items: [ClipItem]) -> [ClipItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { $0.matches(query) }
    }
}

struct HistoryView: View {
    static let width: CGFloat = 380
    static let height: CGFloat = 480

    @ObservedObject var store: HistoryStore
    @ObservedObject var state: PanelState
    let onPaste: (ClipItem) -> Void
    let onCopyOnly: (ClipItem) -> Void
    let onEnableAccessibility: () -> Void

    @FocusState private var searchFocused: Bool

    private var items: [ClipItem] { state.filtered(store.displayItems) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(10)
            Divider()
            if !state.accessibilityTrusted {
                accessibilityBanner
                Divider()
            }
            if items.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
        .onChange(of: state.focusToken) { _, _ in searchFocused = true }
        .onChange(of: state.searchText) { _, _ in state.selectedID = items.first?.id }
    }

    // MARK: - Pieces

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $state.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !state.searchText.isEmpty {
                Button {
                    state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access is needed to paste directly")
                    .font(.caption.weight(.semibold))
                Text("Until then, ↩ copies the item and you press ⌘V yourself.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Enable…", action: onEnableAccessibility)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            store: store,
                            item: item,
                            index: index,
                            isSelected: item.id == state.selectedID,
                            onPin: { store.togglePin(item.id) },
                            onDelete: { store.remove(item.id) }
                        )
                        .id(item.id)
                        .onTapGesture { onPaste(item) }
                        .onHover { hovering in
                            guard hovering,
                                  Date().timeIntervalSince(state.lastKeyboardNavigation) > 0.35 else { return }
                            state.selectedID = item.id
                        }
                        .contextMenu {
                            Button("Paste") { onPaste(item) }
                            Button("Copy to Clipboard") { onCopyOnly(item) }
                            Divider()
                            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item.id) }
                            Button("Delete") { store.remove(item.id) }
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: state.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: state.searchText.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(state.searchText.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.headline)
            Text(state.searchText.isEmpty
                 ? "Copy text, images, or files and they will show up here."
                 : "Try a different search.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("↩ Paste    ⌘⌫ Delete    ⌘P Pin")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if store.items.contains(where: { !$0.pinned }) {
                Button("Clear") { store.clear(keepPinned: true) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Remove all unpinned items")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Row

struct ItemRow: View {
    @ObservedObject var store: HistoryStore
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let onPin: () -> Void
    let onDelete: () -> Void

    private static let maxThumbnail = CGSize(width: 240, height: 96)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                content
                HStack(spacing: 4) {
                    Text(item.subtitle)
                    Text("·")
                    Text(item.date, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if let appIcon = store.appIcon(for: item.sourceBundleID) {
            Image(nsImage: appIcon).resizable()
        } else {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
        }
    }

    private var symbolName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(item.previewText)
                .font(.system(size: 13))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .image:
            if let thumbnail = store.thumbnail(for: item) {
                let size = thumbnailSize
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12)))
            } else {
                Text("Image unavailable")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .files:
            Text(item.fileNames.joined(separator: ", "))
                .font(.system(size: 13))
                .lineLimit(2)
        }
    }

    private var thumbnailSize: CGSize {
        let width = CGFloat(max(item.imageWidth ?? 1, 1))
        let height = CGFloat(max(item.imageHeight ?? 1, 1))
        let scale = min(1, Self.maxThumbnail.width / width, Self.maxThumbnail.height / height)
        return CGSize(width: max(width * scale, 16), height: max(height * scale, 16))
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
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
                .foregroundStyle(.secondary)
            } else if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
