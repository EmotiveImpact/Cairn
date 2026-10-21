import SwiftUI
import AppKit

/// Cairn's graphite identity. The same tokens are used by the established
/// screens and the compact native shell, so navigation never changes theme.
/// Every colour carries a light and a dark value; the window's appearance
/// (Settings › Appearance) decides which one is drawn.
enum Brand {
    // Neutral layers carry the interface; colour identifies actions and status.
    static let chrome = Color(light: 0xE9ECEF, dark: 0x282D33)
    static let background = Color(light: 0xFBFCFD, dark: 0x191D21)
    static let deepPanel = Color(light: 0xF4F6F8, dark: 0x1D2227)
    static let surfaceElevated = Color(light: 0xF1F3F6, dark: 0x252B31)
    static let surfaceSubtle = Color(light: 0xE6EAEE, dark: 0x2A3139)

    static let border = Color(light: 0xD3D9DF, dark: 0x363C43)
    // Sparse structural separators; surfaces and spacing do most of the work.
    static let separator = wash(0.07)
    static let inputBorder = Color(light: 0xB9C2CB, dark: 0x48525D)

    static let textPrimary = Color(light: 0x14191E, dark: 0xF2F4F7)
    static let textSecondary = Color(light: 0x46515C, dark: 0xC4CBD3)
    static let textMuted = Color(light: 0x68727D, dark: 0xABB4BE)

    static let blue = Color(light: 0x1A73E0, dark: 0x58A8F8)
    static let deepBlue = Color(light: 0x1666C9, dark: 0x75BAFF)
    static let cyan = Color(light: 0x1D8BB0, dark: 0x55B5D7)
    static let purple = Color(light: 0x6A5FD6, dark: 0xA39CF2)
    static let safeCyan = Color(light: 0x178A66, dark: 0x61C7A7)
    /// Space you can free, or have freed. Kept for that meaning only.
    static let room = safeCyan
    static let amber = Color(light: 0xA86A08, dark: 0xF0BB61)
    static let danger = Color(light: 0xC93C44, dark: 0xF08086)

    /// The stones in the Home cairn and the result screen.
    static let stoneTop = Color(light: 0xCFD6DD, dark: 0x3A434C)
    static let stoneBase = Color(light: 0xB7C0C9, dark: 0x2B3239)

    /// A neutral tint over the current surface: white on dark, black on light.
    /// Use instead of `Color.white.opacity(_:)` so hovers and fills work in both.
    static func wash(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor.white.withAlphaComponent(opacity)
                              : NSColor.black.withAlphaComponent(opacity * 0.9)
        })
    }

    static let brand = LinearGradient(colors: [Color(hex: 0x3299F5), Color(hex: 0x1375E6)],
                                      startPoint: .top, endPoint: .bottom)
    static let textGradient = LinearGradient(colors: [blue, cyan],
                                              startPoint: .leading, endPoint: .trailing)
    static let ring = AngularGradient(colors: [blue, cyan, blue.opacity(0.45)], center: .center)
    static let panel = LinearGradient(colors: [Color(light: 0xF4F6F8, dark: 0x252B31), Color(light: 0xEDF0F3, dark: 0x181D23)],
                                      startPoint: .top, endPoint: .bottom)
    static let brandWash = LinearGradient(colors: [blue.opacity(0.10), cyan.opacity(0.035)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

    static let rSm: CGFloat = 7
    static let rCard: CGFloat = 10
    static let rHero: CGFloat = 14
    static let rXL: CGFloat = 18
    static let cornerRadius: CGFloat = 10

    static let contentMaxWidth: CGFloat = 1080
    static let rowVPad: CGFloat = 8
    static let colSize: CGFloat = 88
    static let colDate: CGFloat = 112

    static let shadowColor = Color.black
    static let cardShadow = Color.black.opacity(0.16)
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let page: CGFloat = 28
}

enum Elevation {
    case low, med, high
    var opacity: Double { switch self { case .low: return 0.08; case .med: return 0.13; case .high: return 0.19 } }
    var radius: CGFloat { switch self { case .low: return 2; case .med: return 8; case .high: return 18 } }
    var y: CGFloat { switch self { case .low: return 1; case .med: return 3; case .high: return 7 } }
    var color: Color { Brand.shadowColor.opacity(opacity) }
}

struct EyebrowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .heavy)).tracking(1.4)
            .foregroundStyle(Brand.textMuted).textCase(.uppercase)
    }
}
extension View {
    func eyebrow() -> some View { modifier(EyebrowModifier()) }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// A colour that follows the window's light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.isDark ? dark : light)
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
