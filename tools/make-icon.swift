// Draws Sweeply's app icon and writes Resources/AppIcon.icns.
//
//     swift tools/make-icon.swift
//
// Everything is drawn with Core Graphics paths (SF Symbols may not be used in app icons).
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A four-pointed sparkle with curved sides.
func sparkle(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let pinch = r * 0.16
    path.move(to: CGPoint(x: c.x, y: c.y - r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
    path.closeSubpath()
    return path
}

func drawIcon(in ctx: CGContext) {
    // Work top-down, like the design grid.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    // Background tile on the macOS icon grid: 824 pt body, 100 pt margin.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x2F80ED))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x6EE7C8), color(0x2FB3D6), color(0x2F6FE4)] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])
    // Soft light from the top.
    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 160), startRadius: 0,
                           endCenter: CGPoint(x: 380, y: 160), endRadius: 620, options: [])

    // Broom, tilted so it sweeps toward the bottom left.
    ctx.saveGState()
    ctx.translateBy(x: 470, y: 520)
    ctx.rotate(by: 38 * .pi / 180)
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 24, color: color(0x0B3A7A, 0.35))

    // Handle
    let handle = CGPath(roundedRect: CGRect(x: -26, y: -400, width: 52, height: 360),
                        cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.addPath(handle)
    ctx.setFillColor(color(0xFFFFFF, 0.97))
    ctx.fillPath()

    // Brush head: a trapezoid with rounded corners at the bottom.
    let head = CGMutablePath()
    head.move(to: CGPoint(x: -80, y: -40))
    head.addLine(to: CGPoint(x: 80, y: -40))
    head.addLine(to: CGPoint(x: 150, y: 190))
    head.addQuadCurve(to: CGPoint(x: 120, y: 215), control: CGPoint(x: 150, y: 215))
    head.addLine(to: CGPoint(x: -120, y: 215))
    head.addQuadCurve(to: CGPoint(x: -150, y: 190), control: CGPoint(x: -150, y: 215))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Details without the shadow: binding band and bristle lines.
    ctx.saveGState()
    ctx.translateBy(x: 470, y: 520)
    ctx.rotate(by: 38 * .pi / 180)
    let band = CGPath(roundedRect: CGRect(x: -92, y: -58, width: 184, height: 44),
                      cornerWidth: 14, cornerHeight: 14, transform: nil)
    ctx.addPath(band)
    ctx.setFillColor(color(0xD6ECFF))
    ctx.fillPath()
    ctx.setStrokeColor(color(0x2F80ED, 0.22))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    for x in stride(from: -90, through: 90, by: 45) {
        ctx.move(to: CGPoint(x: CGFloat(x) * 0.55, y: 10))
        ctx.addLine(to: CGPoint(x: CGFloat(x) * 1.15, y: 190))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Sparkles where it has swept.
    ctx.setFillColor(color(0xFFFFFF))
    for (x, y, r) in [(700.0, 700.0, 92.0), (792.0, 560.0, 48.0), (300.0, 300.0, 56.0)] {
        ctx.addPath(sparkle(center: CGPoint(x: x, y: y), radius: r))
    }
    ctx.fillPath()
    ctx.restoreGState()
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
drawIcon(in: NSGraphicsContext.current!.cgContext)
NSGraphicsContext.restoreGraphicsState()

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let master = FileManager.default.temporaryDirectory.appending(path: "sweeply-icon-1024.png")
try rep.representation(using: .png, properties: [:])!.write(to: master)

// Every size macOS asks for, then pack them into an .icns.
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let sips = Process()
        sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        sips.arguments = ["-z", "\(pixels)", "\(pixels)", master.path, "--out", iconset.appending(path: name).path]
        sips.standardOutput = FileHandle.nullDevice
        try sips.run()
        sips.waitUntilExit()
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns (preview: \(master.path))")
