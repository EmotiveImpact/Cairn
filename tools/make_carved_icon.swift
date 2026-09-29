import AppKit
import CoreGraphics

// Cairn dark / carved-stone app icon.
// Run: swift selected/make_carved_icon.swift selected/cairn-carved-1024.png
// The image is vector-drawn at 1024 px. Outside the tile is transparent.

private let size = 1024
private let colorSpace = CGColorSpaceCreateDeviceRGB()

private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

private func gradient(_ colors: [CGColor], _ positions: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: positions)!
}

private func stone(_ points: [(CGFloat, CGFloat)], _ controls: [(CGFloat, CGFloat, CGFloat, CGFloat)]) -> CGPath {
    // Each segment is a cubic Bezier from one anchor to the next.
    let p = CGMutablePath()
    p.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for i in controls.indices {
        let c = controls[i]
        let end = points[(i + 1) % points.count]
        p.addCurve(to: CGPoint(x: end.0, y: end.1),
                   control1: CGPoint(x: c.0, y: c.1),
                   control2: CGPoint(x: c.2, y: c.3))
    }
    p.closeSubpath()
    return p
}

private func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for v in points.dropFirst() { p.addLine(to: CGPoint(x: v.0, y: v.1)) }
    p.closeSubpath()
    return p
}

private struct Stone {
    let outline: CGPath
    let topFacet: CGPath
    let rightFacet: CGPath
    let upperY: CGFloat
    let lowerY: CGFloat
}

private let stones: [Stone] = [
    Stone(
        outline: stone(
            [(333, 378), (388, 396), (651, 390), (697, 371),
             (733, 311), (710, 258), (648, 237), (382, 237),
             (301, 260), (291, 305)],
            [(350, 392, 369, 399), (459, 387, 574, 394),
             (673, 389, 688, 382), (715, 354, 731, 328),
             (746, 283, 738, 271), (695, 245, 676, 239),
             (579, 226, 462, 227), (337, 241, 317, 248),
             (280, 275, 285, 290), (306, 341, 317, 369)]),
        topFacet: polygon([(318, 361), (356, 389), (390, 392), (510, 378),
                           (650, 389), (694, 370), (656, 349), (522, 344),
                           (430, 354), (361, 352)]),
        rightFacet: polygon([(650, 389), (697, 371), (733, 311),
                             (710, 258), (648, 237), (675, 289), (661, 342)]),
        upperY: 399, lowerY: 232),
    Stone(
        outline: stone(
            [(374, 514), (416, 533), (619, 529), (657, 514),
             (686, 452), (674, 418), (633, 405), (396, 405),
             (351, 423), (352, 455)],
            [(385, 529, 400, 535), (477, 528, 562, 529),
             (636, 528, 650, 522), (675, 494, 684, 473),
             (689, 436, 684, 425), (661, 409, 649, 405),
             (551, 400, 464, 401), (369, 406, 357, 411),
             (342, 436, 345, 446), (358, 483, 367, 505)]),
        topFacet: polygon([(358, 498), (393, 528), (416, 531), (505, 516),
                           (621, 527), (657, 511), (634, 491), (529, 480),
                           (454, 491), (396, 493)]),
        rightFacet: polygon([(621, 527), (657, 511), (685, 452),
                             (672, 419), (635, 405), (653, 458)]),
        upperY: 533, lowerY: 402),
    Stone(
        outline: stone(
            [(414, 633), (452, 650), (585, 640), (614, 627),
             (639, 585), (627, 554), (586, 540), (434, 541),
             (396, 553), (394, 579)],
            [(423, 647, 438, 651), (494, 644, 552, 646),
             (598, 637, 608, 634), (625, 612, 636, 597),
             (643, 565, 639, 559), (615, 545, 601, 540),
             (530, 538, 479, 540), (409, 542, 401, 547),
             (386, 563, 391, 572), (398, 606, 404, 622)]),
        topFacet: polygon([(397, 612), (433, 642), (453, 648), (524, 628),
                           (589, 639), (615, 627), (591, 608), (516, 600),
                           (452, 609)]),
        rightFacet: polygon([(589, 639), (615, 627), (639, 585),
                             (627, 554), (587, 540), (604, 586)]),
        upperY: 650, lowerY: 538),
    Stone(
        outline: stone(
            [(449, 738), (468, 762), (535, 770), (561, 750),
             (587, 718), (580, 685), (552, 671), (471, 673),
             (437, 692), (439, 714)],
            [(453, 750, 459, 758), (490, 769, 517, 773),
             (546, 767, 552, 757), (575, 738, 587, 729),
             (593, 704, 591, 690), (571, 675, 560, 671),
             (523, 667, 488, 669), (450, 674, 438, 684),
             (432, 701, 436, 707), (440, 726, 445, 735)]),
        topFacet: polygon([(440, 720), (458, 750), (473, 762), (529, 767),
                           (557, 750), (574, 728), (542, 726), (482, 728)]),
        rightFacet: polygon([(557, 751), (587, 718), (580, 685),
                             (552, 671), (568, 709)]),
        upperY: 773, lowerY: 669)
]

guard let context = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("Could not create bitmap context") }

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Graphite tile and restrained dimensional edge.
let tile = CGPath(roundedRect: CGRect(x: 90, y: 90, width: 844, height: 844),
                  cornerWidth: 190, cornerHeight: 190, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 23, color: color(0x000000, 0.28))
context.addPath(tile)
context.setFillColor(color(0x11161B))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
context.drawLinearGradient(
    gradient([color(0x303337), color(0x15171A), color(0x0C0E10)], [0, 0.54, 1]),
    start: CGPoint(x: 278, y: 922), end: CGPoint(x: 762, y: 100),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.restoreGState()

context.addPath(tile)
context.setStrokeColor(color(0x69727B, 0.23))
context.setLineWidth(2)
context.strokePath()

let stonePalettes: [[UInt32]] = [
    [0x155FC5, 0x063D9C, 0x051C63],
    [0x226FD8, 0x0B4AAF, 0x072575],
    [0x2A78E4, 0x1053BE, 0x082C85],
    [0x317FEA, 0x155ACD, 0x09338F]
]
for (index, item) in stones.enumerated() {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -7), blur: 9,
                      color: color(0x000000, 0.46))
    context.addPath(item.outline)
    context.setFillColor(color(0x0A4AAA))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(item.outline)
    context.clip()
    let palette = stonePalettes[index]
    context.drawLinearGradient(
        gradient(palette.map { color($0) }, [0, 0.53, 1]),
        start: CGPoint(x: 403, y: item.upperY),
        end: CGPoint(x: 666, y: item.lowerY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.addPath(item.topFacet)
    context.setFillColor(color(0xA7DAFF, 0.13))
    context.fillPath()
    context.addPath(item.rightFacet)
    context.setFillColor(color(0x063789, 0.23))
    context.fillPath()
    context.restoreGState()

    context.addPath(item.outline)
    context.setStrokeColor(color(0xB8E6FF, 0.14))
    context.setLineWidth(1.5)
    context.strokePath()
}

guard let cgImage = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
else { fatalError("Could not encode PNG") }

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "selected/cairn-carved-1024.png"
try png.write(to: URL(fileURLWithPath: output))
print(output)
