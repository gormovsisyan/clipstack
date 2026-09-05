import AppKit

/// Visual style of the history panel. `classic` is the default; `cards` is an experimental
/// redesign behind a temporary toggle (menu item "New UI (test)" or ⌘T inside the panel).
enum UITheme: String, CaseIterable {
    case classic
    case cards

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .cards: return "Cards"
        }
    }

    /// Window backdrop: translucent popover material for classic, near-solid for cards.
    var material: NSVisualEffectView.Material {
        switch self {
        case .classic: return .popover
        case .cards: return .windowBackground
        }
    }

    var next: UITheme {
        self == .classic ? .cards : .classic
    }

    private static let defaultsKey = "uiTheme"

    static var current: UITheme {
        get { UITheme(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .classic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
