import SwiftUI

/// The established Cairn toolbar mark. Keep its blue tone fixed; the colourful
/// application tile belongs in the Dock, not inside the window chrome.
struct CairnLogo: View {
    var size: CGFloat = 34
    var monochrome = false
    var body: some View {
        VStack(spacing: size * 0.035) {
            stone(width: 0.24, height: 0.12)
            stone(width: 0.40, height: 0.15)
            stone(width: 0.56, height: 0.18)
            stone(width: 0.74, height: 0.23)
        }.frame(width: size, height: size)
    }
    private func stone(width: CGFloat, height: CGFloat) -> some View {
        Ellipse()
            .fill(monochrome ? AnyShapeStyle(Color.black) : AnyShapeStyle(
                LinearGradient(colors: [Color(red: 0.57, green: 0.79, blue: 0.98), Brand.blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .frame(width: size * width, height: size * height)
    }
}

/// A soft layered mountain ridge, anchored to the bottom of its frame.
struct MountainLayer: Shape {
    var drop: CGFloat   // 0…1 fraction of height that pushes the ridgeline down

    func path(in rect: CGRect) -> Path {
        let h = rect.height, w = rect.width, o = drop * h
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.42 + o))
        p.addCurve(to: CGPoint(x: w * 0.18, y: h * 0.48 + o),
                   control1: CGPoint(x: w * 0.06, y: h * 0.22 + o), control2: CGPoint(x: w * 0.12, y: h * 0.62 + o))
        p.addCurve(to: CGPoint(x: w * 0.35, y: h * 0.44 + o),
                   control1: CGPoint(x: w * 0.25, y: h * 0.30 + o), control2: CGPoint(x: w * 0.28, y: h * 0.58 + o))
        p.addCurve(to: CGPoint(x: w * 0.52, y: h * 0.36 + o),
                   control1: CGPoint(x: w * 0.42, y: h * 0.18 + o), control2: CGPoint(x: w * 0.46, y: h * 0.52 + o))
        p.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.45 + o),
                   control1: CGPoint(x: w * 0.61, y: h * 0.18 + o), control2: CGPoint(x: w * 0.65, y: h * 0.58 + o))
        p.addCurve(to: CGPoint(x: w, y: h * 0.34 + o),
                   control1: CGPoint(x: w * 0.82, y: h * 0.20 + o), control2: CGPoint(x: w * 0.92, y: h * 0.60 + o))
        p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
        return p
    }
}

/// A few small pebbles resting beside the cairn on the water.
struct SmallPebbles: View {
    var body: some View {
        HStack(spacing: 18) {
            Capsule().fill(Brand.blue.opacity(0.22)).frame(width: 26, height: 5)
            Capsule().fill(Brand.blue.opacity(0.20)).frame(width: 32, height: 6)
            Capsule().fill(Brand.blue.opacity(0.16)).frame(width: 20, height: 4)
        }
    }
}

/// The hero banner. Uses the bundled `hero.png` artwork if present (the real
/// illustration), otherwise falls back to the drawn `HeroIllustration`.
struct HeroBanner: View {
    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "hero", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    var body: some View {
        GeometryReader { geo in
            if let img = HeroBanner.image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.12)
                    // Top-align the crop so the image's WHITE sky sits behind the
                    // title (not the bluer middle), and the cairn stays visible below.
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()
            } else {
                HeroIllustration()
            }
        }
        .background(Brand.background)
        .allowsHitTesting(false)
    }
}

/// The hero band — mountains rising over still water with the cairn reflected,
/// plus a dusting of particles. Fills its frame (used as a bottom band).
struct HeroIllustration: View {
    private let dots: [(x: CGFloat, y: CGFloat, s: CGFloat, o: Double)] = [
        (0.13, 0.24, 3, 0.26), (0.19, 0.42, 2, 0.22), (0.28, 0.30, 3, 0.20), (0.36, 0.48, 2, 0.28),
        (0.46, 0.22, 3, 0.24), (0.55, 0.38, 2, 0.30), (0.64, 0.18, 3, 0.26), (0.73, 0.36, 2, 0.18),
        (0.82, 0.26, 3, 0.22), (0.91, 0.43, 2, 0.30),
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Brand.background, Brand.deepPanel],
                               startPoint: .top, endPoint: .bottom)

                MountainLayer(drop: 0.16).fill(Brand.blue.opacity(0.16))
                MountainLayer(drop: 0.32).fill(Brand.blue.opacity(0.11))
                MountainLayer(drop: 0.48).fill(Brand.cyan.opacity(0.10))

                // still-water reflection lines near the bottom
                VStack(spacing: 8) {
                    Spacer()
                    Rectangle().fill(.white.opacity(0.45)).frame(height: 1)
                    Rectangle().fill(.white.opacity(0.36)).frame(height: 1).padding(.horizontal, w * 0.10)
                    Rectangle().fill(.white.opacity(0.28)).frame(height: 1).padding(.horizontal, w * 0.20)
                    Rectangle().fill(.white.opacity(0.20)).frame(height: 1).padding(.horizontal, w * 0.30)
                    Spacer().frame(height: 12)
                }

                ForEach(Array(dots.enumerated()), id: \.offset) { _, d in
                    Circle().fill(Brand.blue.opacity(d.o))
                        .frame(width: d.s, height: d.s)
                        .position(x: w * d.x, y: h * d.y)
                }

                CairnLogo(size: min(h * 0.72, 62)).position(x: w * 0.66, y: h * 0.50)
                SmallPebbles().position(x: w * 0.73, y: h * 0.80)
            }
        }
        .allowsHitTesting(false)
    }
}
