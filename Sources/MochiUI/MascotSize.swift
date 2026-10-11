import Foundation

/// User-selectable mascot size.
public enum MascotSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var scale: Double {
        switch self {
        case .small: 0.7
        case .medium: 1.0
        case .large: 1.4
        }
    }

    public var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The speech bubble shrinks less than the figure so its text stays readable (>= ~11pt).
    var bubbleScale: Double { max(scale, 0.85) }
}
