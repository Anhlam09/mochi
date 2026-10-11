import Foundation

/// User-selectable mascot size.
public enum MascotSize: String, CaseIterable, Sendable {
    case tiny, small, medium, large

    public var scale: Double {
        switch self {
        case .tiny: 0.45
        case .small: 0.7
        case .medium: 1.0
        case .large: 1.4
        }
    }

    public var displayName: String {
        switch self {
        case .tiny: "Tiny"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The speech bubble shrinks less than the figure so its text stays readable (>= ~10pt).
    var bubbleScale: Double { max(scale, self == .tiny ? 0.78 : 0.85) }
}
