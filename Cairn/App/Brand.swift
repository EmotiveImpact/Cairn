import SwiftUI

/// Cairn's graphite identity. The same tokens are used by the established
/// screens and the compact native shell, so navigation never changes theme.
enum Brand {
    // Neutral layers carry the interface; colour identifies actions and status.
    static let background = Color(hex: 0x191D21)
    static let deepPanel = Color(hex: 0x1D2227)
    static let surfaceElevated = Color(hex: 0x252B31)
    static let surfaceSubtle = Color(hex: 0x2A3139)

    static let border = Color(hex: 0x363C43)
    // Sparse structural separators; surfaces and spacing do most of the work.
    static let separator = Color.white.opacity(0.07)
    static let inputBorder = Color(hex: 0x48525D)

    static let textPrimary = Color(hex: 0xF2F4F7)
    static let textSecondary = Color(hex: 0xC4CBD3)
    static let textMuted = Color(hex: 0xABB4BE)

    static let blue = Color(hex: 0x58A8F8)
    static let deepBlue = Color(hex: 0x75BAFF)
    static let cyan = Color(hex: 0x55B5D7)
    static let purple = Color(hex: 0xA39CF2)
    static let safeCyan = Color(hex: 0x61C7A7)
    static let amber = Color(hex: 0xF0BB61)
    static let danger = Color(hex: 0xF08086)

    static let brand = LinearGradient(colors: [Color(hex: 0x3299F5), Color(hex: 0x1375E6)],
                                      startPoint: .top, endPoint: .bottom)
    static let textGradient = LinearGradient(colors: [blue, cyan],
                                              startPoint: .leading, endPoint: .trailing)
    static let ring = AngularGradient(colors: [blue, cyan, blue.opacity(0.45)], center: .center)
    static let panel = LinearGradient(colors: [Color(hex: 0x252B31), Color(hex: 0x181D23)],
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

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
