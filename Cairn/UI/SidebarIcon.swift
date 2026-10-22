import SwiftUI

/// The thin line icons from the Night mockup, drawn on a 20 × 20 grid so they
/// match it exactly instead of approximating with SF Symbols.
struct SidebarIcon: View {
    enum Glyph { case home, projects, clean, files, apps, activity, settings }
    let glyph: Glyph
    var size: CGFloat = 16

    var body: some View {
        Glyph.Outline(glyph: glyph)
            .stroke(style: StrokeStyle(lineWidth: 1.6 * size / 20, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

extension SidebarIcon.Glyph {
    fileprivate struct Outline: Shape {
        let glyph: SidebarIcon.Glyph
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 20
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            func poly(_ points: [(CGFloat, CGFloat)], into path: inout Path) {
                path.move(to: p(points[0].0, points[0].1))
                for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
                path.closeSubpath()
            }
            func circle(_ r: CGFloat, into path: inout Path) {
                path.addEllipse(in: CGRect(x: rect.minX + (10 - r) * s, y: rect.minY + (10 - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            var path = Path()
            switch glyph {
            case .home:
                poly([(3, 9), (10, 3), (17, 9), (17, 17), (3, 17)], into: &path)
            case .projects:
                poly([(3, 5), (8, 5), (10, 7), (17, 7), (17, 16), (3, 16)], into: &path)
            case .clean:
                path.move(to: p(10, 3)); path.addLine(to: p(10, 17))
                path.move(to: p(3, 10)); path.addLine(to: p(17, 10))
            case .files:
                poly([(5, 2), (12, 2), (15, 5), (15, 18), (5, 18)], into: &path)
            case .apps:
                for (x, y) in [(3, 3), (11, 3), (3, 11), (11, 11)] as [(CGFloat, CGFloat)] {
                    path.addRoundedRect(in: CGRect(x: rect.minX + x * s, y: rect.minY + y * s, width: 6 * s, height: 6 * s),
                                        cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
                }
            case .activity:
                circle(7, into: &path)
                path.move(to: p(10, 6)); path.addLine(to: p(10, 10)); path.addLine(to: p(13, 12))
            case .settings:
                circle(3, into: &path)
                circle(7, into: &path)
            }
            return path
        }
    }
}
