import AppKit

// Renders a 1024px Cairn app icon: brand gradient squircle + a white "cairn"
// (a balanced stack of stones — the brand mark). Run: swift make_icon.swift <out.png>
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/cairn_icon_1024.png"
let S: CGFloat = 1024

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-rect "squircle" with the standard macOS margin.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius: CGFloat = (S - 2 * inset) * 0.225
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()

// Brand gradient: purple (0x8B5CFF) → blue (0x4DA2FF), top-left → bottom-right.
let purple = CGColor(red: 0x8B/255, green: 0x5C/255, blue: 1.0, alpha: 1)
let blue   = CGColor(red: 0x4D/255, green: 0xA2/255, blue: 1.0, alpha: 1)
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [purple, blue] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: inset, y: S - inset),
                       end: CGPoint(x: S - inset, y: inset), options: [])

// Soft cyan glow top-right (the studio "signature").
let cyan = CGColor(red: 0x58/255, green: 0xF1/255, blue: 0xDA/255, alpha: 0.30)
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [cyan, CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.78, y: S * 0.80), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.78, y: S * 0.80), endRadius: S * 0.5, options: [])

// The cairn: a stack of white stones (ellipses), widest at the base.
// (cx, cy, w, h) in CG coords (y up). Small gaps between each.
let cx: CGFloat = S / 2
let stones: [(CGFloat, CGFloat, CGFloat)] = [
    // (cy, width, height)
    (360, 380, 150),
    (505, 300, 126),
    (625, 224, 106),
    (725, 150,  86),
]
for (i, s) in stones.enumerated() {
    let (cy, w, h) = s
    let r = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    // Top stones very slightly translucent for gentle depth.
    let alpha = 1.0 - CGFloat(i) * 0.04
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    ctx.addEllipse(in: r)
    ctx.fillPath()
}
ctx.restoreGState()

image.unlockFocus()

if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: outPath))
    FileHandle.standardError.write("icon -> \(outPath)\n".data(using: .utf8)!)
} else {
    FileHandle.standardError.write("icon FAILED\n".data(using: .utf8)!)
}
