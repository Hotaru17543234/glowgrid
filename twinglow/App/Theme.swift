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
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Same neutrals and firefly glow as 萤格, so the two apps feel like siblings.
enum Theme {
    static let paper = Color.dyn(0xF3F5F1, 0x13171A)
    static let ink = Color.dyn(0x22303A, 0xE4E9EB)
    static let muted = Color.dyn(0x75838C, 0x8E9AA1)
    static let line = Color.dyn(0xD9E0DE, 0x2C343A)
    static let glow = Color.dyn(0xB9DB2E, 0xE6F77A)
}

/// The colour an account wears. The raw value is what gets saved, so only ever append new cases.
enum Glow: Int, CaseIterable, Identifiable {
    case firefly, sky, sakura, yuzu, fuji, mint

    var id: Int { rawValue }

    var hexes: (UInt32, UInt32) {
        switch self {
        case .firefly: return (0x9CC92A, 0xD6F06A)
        case .sky: return (0x5FA3E6, 0x8FC4F5)
        case .sakura: return (0xEC8AA6, 0xF4A6BA)
        case .yuzu: return (0xE8B730, 0xF2CB4E)
        case .fuji: return (0x9C84DB, 0xB9A4EC)
        case .mint: return (0x3FBF95, 0x6FD3AE)
        }
    }

    var color: Color { Color.dyn(hexes.0, hexes.1) }

    var name: String {
        switch self {
        case .firefly: return "萤绿"
        case .sky: return "天蓝"
        case .sakura: return "樱粉"
        case .yuzu: return "柚黄"
        case .fuji: return "藤紫"
        case .mint: return "薄荷"
        }
    }
}
