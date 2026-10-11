import SwiftUI
import AppKit

/// Mochi's pastel palette. Every colour adapts to light / dark appearance.
public enum Palette {
    static func rgb(_ hex: UInt32, alpha: Double = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha))
    }

    static func dynamic(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha: alpha)
        })
    }

    public static let body = dynamic(light: 0xFFE9EC, dark: 0xF4C9D2)
    public static let blush = dynamic(light: 0xFFB3C1, dark: 0xE89AAB)
    public static let sprout = dynamic(light: 0xA8E6CF, dark: 0x7FCDAE)
    public static let peach = dynamic(light: 0xFFD8A8, dark: 0xF0BE85)
    public static let focusRing = dynamic(light: 0xB5A8FF, dark: 0x9A8CF0)
    public static let breakRing = dynamic(light: 0x8FD9F0, dark: 0x6CC3DE)
    /// Dark ink: used for eyes/mouth. Does NOT flip in dark mode (the body stays light).
    public static let ink = Color(nsColor: rgb(0x4A3F55))
    /// Text ink: flips to light in dark mode.
    public static let text = dynamic(light: 0x4A3F55, dark: 0xF3EEF7)
    public static let bubbleBackground = dynamic(light: 0xFFFFFF, dark: 0x3A3345, alpha: 0.92)
}

extension Font {
    static func mochi(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Mochi's colour flavours (body, cheeks and sprout). Inspired by classic kawaii pastels:
/// pastel pink #FFB3C1, mint #B5EAD7, lavender #C9AEFF, sky blue #9AD0FF, peach #FFC29B.
public enum MochiFlavor: String, CaseIterable, Sendable {
    case strawberry, matcha, taro, ramune, peach, banana

    public var displayName: String {
        switch self {
        case .strawberry: "Strawberry"
        case .matcha: "Matcha"
        case .taro: "Taro"
        case .ramune: "Ramune"
        case .peach: "Peach"
        case .banana: "Banana"
        }
    }

    public var emoji: String {
        switch self {
        case .strawberry: "🍓"
        case .matcha: "🍵"
        case .taro: "🍠"
        case .ramune: "🫧"
        case .peach: "🍑"
        case .banana: "🍌"
        }
    }

    /// The flavour after this one, wrapping around.
    public var next: MochiFlavor {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    public var body: Color {
        switch self {
        case .strawberry: Palette.body
        case .matcha: Palette.dynamic(light: 0xE4F6EC, dark: 0xBFE6D0)
        case .taro: Palette.dynamic(light: 0xEEE6FF, dark: 0xD5C5F7)
        case .ramune: Palette.dynamic(light: 0xE2F1FF, dark: 0xC0DDF8)
        case .peach: Palette.dynamic(light: 0xFFEADB, dark: 0xF7CDAE)
        case .banana: Palette.dynamic(light: 0xFFF5D6, dark: 0xF2E0A6)
        }
    }

    public var blush: Color {
        switch self {
        case .strawberry, .matcha, .taro, .ramune: Palette.blush
        case .peach: Palette.dynamic(light: 0xFFA8A0, dark: 0xEC8F86)
        case .banana: Palette.dynamic(light: 0xFFC29B, dark: 0xF0A77C)
        }
    }

    public var sprout: Color {
        switch self {
        case .matcha: Palette.dynamic(light: 0x8FD3A6, dark: 0x6FBE8B)
        case .taro: Palette.dynamic(light: 0xB5EAD7, dark: 0x8FD3B8)
        default: Palette.sprout
        }
    }
}

private struct FlavorKey: EnvironmentKey { static let defaultValue = MochiFlavor.strawberry }
extension EnvironmentValues {
    /// Colour flavour the mascot draws with.
    public var mochiFlavor: MochiFlavor {
        get { self[FlavorKey.self] }
        set { self[FlavorKey.self] = newValue }
    }
}
