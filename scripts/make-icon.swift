// Renders Utter's app icon to Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let violet = CGColor(red: 0.49, green: 0.36, blue: 1.00, alpha: 1)
let magenta = CGColor(red: 0.93, green: 0.35, blue: 0.70, alpha: 1)
let amber = CGColor(red: 1.00, green: 0.62, blue: 0.32, alpha: 1)
let space = CGColorSpaceCreateDeviceRGB()

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// Draws on a 1024×1024 canvas (origin bottom-left), using Apple's icon grid:
/// an 824pt rounded square centered with a 100pt margin.
func draw(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: CGColor(gray: 0, alpha: 0.4))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Deep indigo-to-black background.
    ctx.drawLinearGradient(
        gradient([CGColor(red: 0.12, green: 0.08, blue: 0.25, alpha: 1), CGColor(red: 0.03, green: 0.02, blue: 0.06, alpha: 1)], [0, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
    )

    // Soft aurora glow behind the waveform.
    ctx.drawRadialGradient(
        gradient([magenta.copy(alpha: 0.55)!, violet.copy(alpha: 0.22)!, violet.copy(alpha: 0)!], [0, 0.5, 1]),
        startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 500), endRadius: 420, options: []
    )

    // Waveform: seven rounded bars, tallest in the middle.
    let heights: [CGFloat] = [0.28, 0.50, 0.78, 1.0, 0.78, 0.50, 0.28]
    let barWidth: CGFloat = 56
    let gap: CGFloat = 34
    let maxHeight: CGFloat = 420
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let bars = CGMutablePath()
    for (i, h) in heights.enumerated() {
        let height = maxHeight * h
        let rect = CGRect(
            x: 512 - totalWidth / 2 + CGFloat(i) * (barWidth + gap),
            y: 512 - height / 2, width: barWidth, height: height
        )
        bars.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    }

    // Glow pass, then the gradient-filled bars on top.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: magenta.copy(alpha: 0.9)!)
    ctx.addPath(bars)
    ctx.setFillColor(magenta)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bars)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([violet, magenta, amber], [0, 0.5, 1]),
        start: CGPoint(x: 230, y: 700), end: CGPoint(x: 794, y: 324), options: []
    )
    ctx.restoreGState()

    // Glass highlight across the top half.
    ctx.drawLinearGradient(
        gradient([CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)], [0, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: []
    )
    ctx.restoreGState()

    // Hairline rim.
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and Resources/AppIcon.png" : "iconutil failed")
