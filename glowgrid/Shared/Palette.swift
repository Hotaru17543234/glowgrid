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
    /// (light, dark) base colours. Hues are spread around the wheel so tags stay easy to tell apart.
    var hexes: (UInt32, UInt32) {
        switch self {
        case .sakura: return (0xF4A6BA, 0xE0849A)
        case .crimson: return (0xE8626B, 0xE0565F)
        case .persimmon: return (0xF39A4F, 0xDD8B42)
        case .yuzu: return (0xF2CB4E, 0xD9AE3A)
        case .matcha: return (0x9CCB74, 0x7DB06B)
        case .mint: return (0x6FD3AE, 0x4FB58F)
        case .teal: return (0x55BFCB, 0x3FA3B0)
        case .sky: return (0x7FB2EA, 0x6E9CD3)
        case .indigo: return (0x7F89E6, 0x6E78D0)
        case .fuji: return (0xB49DE3, 0x9A84CF)
        case .grape: return (0xCF7FD6, 0xB066B8)
        case .cocoa: return (0xC09271, 0xA27A5C)
        case .slate: return (0x8FA3B6, 0x7A8EA2)
        case .sumi: return (0x6E7783, 0x9AA4B0)
        }
    }

    /// Full colour, for dots and bars.
    var color: Color { Color.dyn(hexes.0, hexes.1) }

    /// A clearly darker (light mode) / lighter (dark mode) edge, so each tag has a crisp boundary.
    var border: Color {
        Color.dyn(Color.mixHex(hexes.0, 0x000000, 0.72),
                  Color.mixHex(hexes.1, 0xFFFFFF, 0.78))
    }

    /// Soft fill behind text in the day grid.
    var tint: Color {
        Color.dyn(Color.mixHex(hexes.0, Palette.sheetHex.0, 0.30),
                  Color.mixHex(hexes.1, Palette.sheetHex.1, 0.32))
    }

    /// Slightly stronger fill for small chips.
    var chip: Color {
        Color.dyn(Color.mixHex(hexes.0, Palette.sheetHex.0, 0.42),
                  Color.mixHex(hexes.1, Palette.sheetHex.1, 0.45))
    }
}

/// The decoration of a tag. Everything is drawn on the right side and fades out towards the
/// text, so the title always sits on a calm background.
struct PatternOverlay: View {
    let pattern: TaskPattern
    let color: TaskColor

    var body: some View {
        switch pattern {
        case .solid:
            Color.clear
        case .gradient:
            LinearGradient(colors: [color.color.opacity(0), color.color.opacity(0.6)],
                           startPoint: .leading, endPoint: .trailing)
        case .ribbon:
            RibbonBand()
        case .stripes:
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 7
                }
                ctx.stroke(p, with: .color(color.color.opacity(0.55)), lineWidth: 2)
            }
            .mask { Self.fadeMask }
        case .dots:
            Canvas { ctx, size in
                var y: CGFloat = 4
                var row = 0
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? 4 : 9
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)),
                                 with: .color(color.color.opacity(0.7)))
                        x += 10
                    }
                    y += 8
                    row += 1
                }
            }
            .mask { Self.fadeMask }
        case .sparkle:
            Canvas { ctx, size in
                let spots: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.93, 0.30, 5), (0.82, 0.68, 3.5), (0.72, 0.22, 2.5), (0.97, 0.80, 2.5), (0.64, 0.62, 2)
                ]
                for (fx, fy, r) in spots {
                    let c = CGPoint(x: size.width * fx, y: min(size.height - r, max(r, size.height * fy)))
                    var star = Path()
                    star.move(to: CGPoint(x: c.x, y: c.y - r))
                    star.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
                    star.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
                    star.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
                    star.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
                    ctx.fill(star, with: .color(color.border.opacity(0.8)))
                }
            }
        }
    }

    static let fadeMask = LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.5), .init(color: .black, location: 1)],
        startPoint: .leading, endPoint: .trailing)
}

/// A short rainbow sash at the trailing edge, like a ribbon tied to the tag.
struct RibbonBand: View {
    static let colors: [TaskColor] = [.crimson, .persimmon, .yuzu, .mint, .sky, .fuji]

    var body: some View {
        Canvas { ctx, size in
            let stripe: CGFloat = 4
            let slant: CGFloat = min(size.height * 0.6, 14)
            let bandWidth = stripe * CGFloat(Self.colors.count)
            let x0 = size.width - bandWidth - 6
            for (i, c) in Self.colors.enumerated() {
                let x = x0 + CGFloat(i) * stripe
                var p = Path()
                p.move(to: CGPoint(x: x + slant, y: 0))
                p.addLine(to: CGPoint(x: x + slant + stripe, y: 0))
                p.addLine(to: CGPoint(x: x + stripe, y: size.height))
                p.addLine(to: CGPoint(x: x, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(c.color.opacity(0.9)))
            }
        }
    }
}
