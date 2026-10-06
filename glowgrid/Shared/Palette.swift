import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1)
    }
}

extension Color {
    /// A colour with separate light and dark values.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// Mix two hex colours; t is the share of `a`.
    static func mixHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) * t + ch(b, s) * (1 - t)).rounded()) }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Same tokens as the web prototype: grid-paper neutrals, firefly glow, Japanese weekend colours.
enum Palette {
    static let paperHex: (UInt32, UInt32) = (0xF3F5F1, 0x13171A)
    static let sheetHex: (UInt32, UInt32) = (0xFFFFFF, 0x1B2024)

    static let paper = Color.dyn(0xF3F5F1, 0x13171A)
    static let sheet = Color.dyn(0xFFFFFF, 0x1B2024)
    static let ink = Color.dyn(0x22303A, 0xE4E9EB)
    static let muted = Color.dyn(0x75838C, 0x8E9AA1)
    static let line = Color.dyn(0xE4E9E7, 0x252C31)
    static let lineStrong = Color.dyn(0xC7D0D0, 0x38434A)
    static let accent = Color.dyn(0x3D7A69, 0x7CC4AE)
    static let now = Color.dyn(0xDD5145, 0xFF6A5C)
    static let sat = Color.dyn(0x3B74C2, 0x7FA9E3)
    static let sun = Color.dyn(0xCF4B3B, 0xF08471)
    static let glowBG = Color.dyn(0xE3F18A, 0x3E4917)
    static let glowInk = Color.dyn(0x2F3B0E, 0xE3F18A)
    static let spark = Color.dyn(0xB9DB2E, 0xE6F77A)
}

extension TaskColor {
    private var hexes: (UInt32, UInt32) {
        switch self {
        case .sakura: return (0xF0A3B4, 0xE0849A)
        case .matcha: return (0x97C785, 0x7DB06B)
        case .sky: return (0x8AB5E6, 0x6E9CD3)
        case .yuzu: return (0xF0C25E, 0xD9A840)
        case .fuji: return (0xB4A0DE, 0x9A84CF)
        }
    }

    /// Full colour, for borders, dots and colour bars.
    var color: Color { Color.dyn(hexes.0, hexes.1) }

    /// Soft fill behind text (the colour mixed into the sheet).
    var tint: Color {
        Color.dyn(Color.mixHex(hexes.0, Palette.sheetHex.0, 0.32),
                  Color.mixHex(hexes.1, Palette.sheetHex.1, 0.32))
    }

    /// Slightly stronger fill for the small month chips.
    var chip: Color {
        Color.dyn(Color.mixHex(hexes.0, Palette.sheetHex.0, 0.45),
                  Color.mixHex(hexes.1, Palette.sheetHex.1, 0.45))
    }
}
