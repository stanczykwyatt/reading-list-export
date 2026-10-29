// Draws the app icon and writes it to Resources/AppIcon.icns, plus docs/icon.png for the website.
//
//   swift scripts/make-icon.swift
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

/// Draws the icon on a 1024-point canvas, scaled to `pixels`.
func icon(pixels: Int) -> NSBitmapImageRep {
    let image = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    let slate = NSColor(srgbRed: 0.13, green: 0.17, blue: 0.27, alpha: 1)
    let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)

    // The rounded tile, with the soft shadow macOS icons sit on. Same tile and light as Show Desktop.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = .black.withAlphaComponent(0.3)
    tileShadow.shadowBlurRadius = 24
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    tileShadow.set()
    slate.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(srgbRed: 0.80, green: 0.87, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.45, green: 0.57, blue: 0.75, alpha: 1),
        slate,
    ])!.draw(in: tile, angle: -90)

    /// A rounded bar, with a soft shadow, or glowing in `color` when it's the newest part.
    func bar(_ rect: NSRect, color: NSColor, glow: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        if glow {
            shadow.shadowColor = color.withAlphaComponent(0.75)
            shadow.shadowBlurRadius = 34
        } else {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 10
            shadow.shadowOffset = NSSize(width: 0, height: -6)
        }
        shadow.set()
        color.setFill()
        let radius = min(rect.width, rect.height) / 2
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The page: a white sheet with rounded corners and a soft shadow.
    func sheet(_ rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // A saved page with a ribbon marking your place, and lines of text below it. The ribbon glows
    // in ice blue against the slate, and the page's lines are slate on white.
    let page = NSRect(x: 282, y: 214, width: 460, height: 596)
    sheet(page)
    let ribbon = NSBezierPath()
    let left: CGFloat = 352, right: CGFloat = 472, top = page.maxY + 26
    ribbon.move(to: NSPoint(x: left, y: top))
    ribbon.line(to: NSPoint(x: right, y: top))
    ribbon.line(to: NSPoint(x: right, y: top - 250))
    ribbon.line(to: NSPoint(x: (left + right) / 2, y: top - 196))
    ribbon.line(to: NSPoint(x: left, y: top - 250))
    ribbon.close()
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = ice.withAlphaComponent(0.8)
    glow.shadowBlurRadius = 36
    glow.set()
    ice.setFill()
    ribbon.fill()
    NSGraphicsContext.restoreGraphicsState()
    let lines: [CGFloat] = [300, 252, 300, 196]
    for (index, length) in lines.enumerated() {
        let y = 470 - CGFloat(index) * 66
        bar(NSRect(x: 352, y: y, width: length, height: 34), color: slate.withAlphaComponent(index == 0 ? 0.85 : 0.45), glow: false)
    }

    NSGraphicsContext.restoreGraphicsState()
    return image
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = icon(pixels: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try icon(pixels: 256).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
Swift.print("Wrote \(output) and docs/icon.png")
