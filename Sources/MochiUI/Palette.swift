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
