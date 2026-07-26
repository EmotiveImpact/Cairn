import SwiftUI

/// Cairn's LIGHT identity — soft blue-white surfaces, a blue→teal gradient, deep
/// slate text. Token names are kept stable so every view re-skins automatically.
/// (Background image slot is layered in by `AppBackground` later.)
enum Brand {
    // Surfaces — light, layered
    static let background = Color(hex: 0xF3F7FE)        // app/content background
    static let deepPanel = Color(hex: 0xFFFFFF)         // sidebar
    static let surfaceElevated = Color(hex: 0xFFFFFF)   // cards, raised UI
    static let surfaceSubtle = Color(hex: 0xF6F9FE)     // subtle fills / hover

    // Hairlines / dividers
    static let border = Color(hex: 0xE4ECF7)
    static let inputBorder = Color(hex: 0xD3DEEC)

    // Text — deep navy/slate
    static let textPrimary = Color(hex: 0x1E2A44)
    static let textSecondary = Color(hex: 0x5A6B86)
    static let textMuted = Color(hex: 0x8593AD)   // one step deeper for legible captions

    // Accents — blue leads, teal/cyan is the gradient partner
    static let blue = Color(hex: 0x3D7DFF)              // primary
    static let deepBlue = Color(hex: 0x2348B5)          // deep navy-blue (card icons)
    static let cyan = Color(hex: 0x34D2C4)              // teal
    static let purple = Color(hex: 0x6E8BFF)            // soft indigo (sparingly)
    static let safeCyan = Color(hex: 0x16B8A6)          // "safe" ticks
    static let amber = Color(hex: 0xF5A623)             // REVIEW / attention
    static let danger = Color(hex: 0xFF5C6C)            // RISKY / destructive

    // Gradients
    /// Primary button / ring fill (blue → teal)
    static let brand = LinearGradient(colors: [blue, cyan], startPoint: .leading, endPoint: .trailing)
    /// Big-number / headline gradient (blue → teal)
    static let textGradient = LinearGradient(colors: [blue, cyan], startPoint: .leading, endPoint: .trailing)
    /// Ring sweep (blue → teal, top arc)
    static let ring = AngularGradient(colors: [blue, cyan, blue.opacity(0.4)], center: .center)
    /// Panel background (white → faint blue)
    static let panel = LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xEEF4FD)],
                                      startPoint: .top, endPoint: .bottom)
    /// A barely-there brand wash for large lit surfaces (hero, ambient field).
    static let brandWash = LinearGradient(colors: [blue.opacity(0.06), cyan.opacity(0.04)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

    // Radius scale (premium = a deliberate, consistent set)
    static let rSm: CGFloat = 8
    static let rCard: CGFloat = 14
    static let rHero: CGFloat = 20
    static let rXL: CGFloat = 22
    static let cornerRadius: CGFloat = 14   // legacy alias → rCard

    // Layout
    static let contentMaxWidth: CGFloat = 1080
    static let rowVPad: CGFloat = 12
    // Shared table columns so size/date figures align across tabs.
    static let colSize: CGFloat = 88
    static let colDate: CGFloat = 112

    /// Base shadow tint for the elevation ramp (see `Elevation`).
    static let shadowColor = Color(hex: 0x1E2A44)
    /// Soft card shadow (light theme) — legacy single value.
    static let cardShadow = Color(hex: 0x1E2A44).opacity(0.06)
}

/// A consistent 4/8-based spacing scale. Premium layouts read as premium because
/// every gap comes from one ramp, not ad-hoc numbers.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let page: CGFloat = 28
}

/// Three-step elevation ramp. Real depth (soft, layered shadows) reads far more
/// premium than the same 1px hairline on every surface.
enum Elevation {
    case low, med, high
    var opacity: Double { switch self { case .low: return 0.045; case .med: return 0.07; case .high: return 0.10 } }
    var radius: CGFloat { switch self { case .low: return 3; case .med: return 10; case .high: return 24 } }
    var y: CGFloat { switch self { case .low: return 1; case .med: return 4; case .high: return 10 } }
    var color: Color { Brand.shadowColor.opacity(opacity) }
}

/// Tiny all-caps section label ("eyebrow") used above headers/metrics.
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

extension Color {
    /// Color(hex: 0x3D7DFF) — opaque RGB from a 24-bit hex literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
