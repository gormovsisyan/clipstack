import AppKit
import SwiftUI

/// UI state shared between the SwiftUI views and the panel controller.
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

/// Root view: owns focus and selection bookkeeping; the layout lives in HistoryContentView.
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
        HistoryContentView(store: store, state: state, items: items, searchFocused: $searchFocused,
                           onPaste: onPaste, onCopyOnly: onCopyOnly,
                           onEnableAccessibility: onEnableAccessibility)
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

// MARK: - Model helpers

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
