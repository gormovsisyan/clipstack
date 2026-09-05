import AppKit
import SwiftUI

/// UI state shared between the SwiftUI views and the panel controller.
final class PanelState: ObservableObject {
    @Published var searchText = ""
    @Published var selectedID: UUID?
    @Published var accessibilityTrusted = true
    @Published var focusToken = 0
    @Published var theme: UITheme = UITheme.current {
        didSet { UITheme.current = theme }
    }
    /// Hover-selection is suppressed briefly after keyboard navigation so the list scrolling
    /// underneath a stationary cursor does not steal the selection.
    var lastKeyboardNavigation: Date = .distantPast

    func filtered(_ items: [ClipItem]) -> [ClipItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { $0.matches(query) }
    }
}

/// Root view: owns focus and selection bookkeeping, delegates the look to the active theme.
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
        Group {
            switch state.theme {
            case .classic:
                ClassicHistoryView(store: store, state: state, items: items, searchFocused: $searchFocused,
                                   onPaste: onPaste, onCopyOnly: onCopyOnly,
                                   onEnableAccessibility: onEnableAccessibility)
            case .cards:
                CardsHistoryView(store: store, state: state, items: items, searchFocused: $searchFocused,
                                 onPaste: onPaste, onCopyOnly: onCopyOnly,
                                 onEnableAccessibility: onEnableAccessibility)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
        .onChange(of: state.focusToken) { _, _ in searchFocused = true }
        .onChange(of: state.searchText) { _, _ in state.selectedID = items.first?.id }
    }
}

// MARK: - Shared pieces

/// Scrolling list with selection, hover, tap-to-paste and context menu; the row look is injected.
struct ItemListView<Row: View>: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var state: PanelState
    let items: [ClipItem]
    let spacing: CGFloat
    let padding: CGFloat
    let onPaste: (ClipItem) -> Void
    let onCopyOnly: (ClipItem) -> Void
    let row: (ClipItem, Int, Bool) -> Row

    init(store: HistoryStore, state: PanelState, items: [ClipItem], spacing: CGFloat, padding: CGFloat,
         onPaste: @escaping (ClipItem) -> Void, onCopyOnly: @escaping (ClipItem) -> Void,
         @ViewBuilder row: @escaping (ClipItem, Int, Bool) -> Row) {
        self.store = store
        self.state = state
        self.items = items
        self.spacing = spacing
        self.padding = padding
        self.onPaste = onPaste
        self.onCopyOnly = onCopyOnly
        self.row = row
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, index, item.id == state.selectedID)
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
                .padding(padding)
            }
            .onChange(of: state.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }
}

struct AccessibilityBanner: View {
    let onEnable: () -> Void

    var body: some View {
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
            Button("Enable…", action: onEnable)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

struct EmptyStateView: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : "clipboard")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(searching ? "No matches" : "Nothing copied yet")
                .font(.headline)
            Text(searching ? "Try a different search." : "Copy text, images, or files and they will show up here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Classic theme

struct ClassicHistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var state: PanelState
    let items: [ClipItem]
    let searchFocused: FocusState<Bool>.Binding
    let onPaste: (ClipItem) -> Void
    let onCopyOnly: (ClipItem) -> Void
    let onEnableAccessibility: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(10)
            Divider()
            if !state.accessibilityTrusted {
                AccessibilityBanner(onEnable: onEnableAccessibility)
                Divider()
            }
            if items.isEmpty {
                EmptyStateView(searching: !state.searchText.isEmpty)
            } else {
                ItemListView(store: store, state: state, items: items, spacing: 2, padding: 6,
                             onPaste: onPaste, onCopyOnly: onCopyOnly) { item, index, isSelected in
                    ItemRow(store: store, item: item, index: index, isSelected: isSelected,
                            onPin: { store.togglePin(item.id) },
                            onDelete: { store.remove(item.id) })
                }
            }
            Divider()
            footer
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $state.searchText)
                .textFieldStyle(.plain)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private var footer: some View {
        HStack {
            Text("↩ Paste    ⌘⌫ Delete    ⌘P Pin    ⌘T Style")
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
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(.secondary)
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
                let size = item.thumbnailSize(fitting: Self.maxThumbnail)
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

// MARK: - Model helpers used by both themes

extension ClipItem.Kind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }

    var label: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .files: return "Files"
        }
    }
}

extension ClipItem {
    /// Display size for the stored image, scaled down (never up) to fit `box`.
    func thumbnailSize(fitting box: CGSize) -> CGSize {
        let width = CGFloat(max(imageWidth ?? 1, 1))
        let height = CGFloat(max(imageHeight ?? 1, 1))
        let scale = min(1, box.width / width, box.height / height)
        return CGSize(width: max(width * scale, 16), height: max(height * scale, 16))
    }
}
