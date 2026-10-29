// Draws the README demo (docs/demo.gif) and the link preview image (docs/social.png).
// Everything is drawn here rather than recorded, so the art never shows anyone's real desktop or
// Reading List. The pages, their sites and the notes app are all made up.
//
//   swift scripts/make-art.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let ink = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)
let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)

func bitmap(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Cool silver light on a dark wallpaper, like Show Desktop's art.
func wallpaper(_ rect: NSRect) {
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), ending: ink)!.draw(in: rect, angle: -90)
    let glows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.18, 0.75, 0.42, NSColor(srgbRed: 0.84, green: 0.89, blue: 0.95, alpha: 0.45)),
        (0.85, 0.72, 0.38, NSColor(srgbRed: 0.59, green: 0.68, blue: 0.81, alpha: 0.40)),
        (0.70, 0.12, 0.46, NSColor(srgbRed: 0.75, green: 0.81, blue: 0.89, alpha: 0.32)),
        (0.22, 0.15, 0.30, NSColor(srgbRed: 0.44, green: 0.53, blue: 0.65, alpha: 0.32)),
    ]
    for (x, y, r, color) in glows {
        let center = NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        NSGradient(starting: color, ending: color.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width * r, options: [])
    }
}

func symbol(_ name: String, size: CGFloat, colors: [NSColor], weight: NSFont.Weight = .regular) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

@discardableResult
func text(
    _ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
    centered: Bool = false, mono: Bool = false
) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (string as NSString).size(withAttributes: attributes).width
    (string as NSString).draw(at: NSPoint(x: centered ? point.x - width / 2 : point.x, y: point.y), withAttributes: attributes)
    return width
}

/// A dark app window with a title bar. Returns the content area.
@discardableResult
func window(_ frame: NSRect, title: String, alpha: CGFloat = 1, scale: CGFloat = 1, key: Bool) -> NSRect {
    let rect = NSRect(
        x: frame.midX - frame.width * scale / 2, y: frame.midY - frame.height * scale / 2,
        width: frame.width * scale, height: frame.height * scale
    )
    let body = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent((key ? 0.55 : 0.35) * alpha)
    shadow.shadowBlurRadius = key ? 30 : 18
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.19, alpha: alpha).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12 * alpha).setStroke()
    body.lineWidth = 1
    body.stroke()
    let colors: [NSColor] = key ? [.systemRed, .systemYellow, .systemGreen] : [.gray, .gray, .gray]
    for (index, color) in colors.enumerated() {
        color.withAlphaComponent(alpha * (key ? 1 : 0.5)).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 14 + CGFloat(index) * 18, y: rect.maxY - 22, width: 11, height: 11)).fill()
    }
    text(title, at: NSPoint(x: rect.midX, y: rect.maxY - 24), size: 12, weight: .semibold, color: .white.withAlphaComponent((key ? 0.85 : 0.45) * alpha), centered: true)
    return NSRect(x: rect.minX + 18, y: rect.minY + 14, width: rect.width - 36, height: rect.height - 50)
}

func cursor(at point: NSPoint, pressed: Bool) {
    let arrow = NSBezierPath()
    let s: CGFloat = pressed ? 0.9 : 1
    arrow.move(to: point)
    arrow.line(to: NSPoint(x: point.x, y: point.y - 22 * s))
    arrow.line(to: NSPoint(x: point.x + 5.5 * s, y: point.y - 17 * s))
    arrow.line(to: NSPoint(x: point.x + 9.5 * s, y: point.y - 25.5 * s))
    arrow.line(to: NSPoint(x: point.x + 13 * s, y: point.y - 24 * s))
    arrow.line(to: NSPoint(x: point.x + 9 * s, y: point.y - 15.5 * s))
    arrow.line(to: NSPoint(x: point.x + 16 * s, y: point.y - 15.5 * s))
    arrow.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    NSColor.black.setFill()
    arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setStroke()
    arrow.lineWidth = 1.5
    arrow.stroke()
}

// MARK: Scene

let width: CGFloat = 720
let height: CGFloat = 450
let menuBarHeight: CGFloat = 26
let iconCenter = NSPoint(x: width - 168, y: height - menuBarHeight / 2)
let notesFrame = NSRect(x: 30, y: 24, width: 520, height: 372)

/// The files the export writes, in the order they appear.
let files = [
    ("Reading List.md", "14 pages · 8 unread"),
    ("Reading List.html", "bookmarks file · for Linkding"),
    ("Reading List.csv", "Instapaper layout · Wallabag"),
]

/// The note's pages: unread first, then read ones checked off.
let unread: [(String, String)] = [
    ("How tide pools survive the winter", "Tide Watch · added 04-30"),
    ("A field guide to city lichens", "Lichen Society · added 04-29"),
    ("The quiet economics of public libraries", "The Ledger · added 04-27"),
]
let finished: [(String, String)] = [
    ("Why trains run late in the snow", "rails.example.net · read 04-29"),
    ("Learning to sharpen a kitchen knife", "whetstone.example.com · read 04-26"),
]

struct Moment {
    var shown = 0
    var note = false
    var cursorAt = NSPoint(x: 600, y: 120)
    var pressed = false
    var menuOpen = false
    var hovering = false
}

/// A notes app with a folder of files on the left and the open note on the right. Plain and made
/// up, not any real app.
func notes(_ m: Moment) {
    let page = window(notesFrame, title: "Notebook — Reading", key: !m.menuOpen)
    let sidebar = NSRect(x: page.minX - 6, y: page.minY - 2, width: 178, height: page.height + 2)
    NSColor.white.withAlphaComponent(0.04).setFill()
    NSBezierPath(roundedRect: sidebar, xRadius: 6, yRadius: 6).fill()
    var y = sidebar.maxY - 20
    symbol("folder.fill", size: 11, colors: [ice]).draw(at: NSPoint(x: sidebar.minX + 8, y: y - 1), from: .zero, operation: .sourceOver, fraction: 1)
    text("Reading", at: NSPoint(x: sidebar.minX + 26, y: y), size: 11.5, weight: .semibold, color: .white.withAlphaComponent(0.85))
    if m.shown == 0 {
        text("Empty", at: NSPoint(x: sidebar.minX + 26, y: y - 22), size: 11, color: .white.withAlphaComponent(0.35))
    }
    for (index, file) in files.prefix(m.shown).enumerated() {
        y -= 40
        let open = m.note && index == 0
        if open {
            NSColor.systemBlue.withAlphaComponent(0.32).setFill()
            NSBezierPath(roundedRect: NSRect(x: sidebar.minX + 4, y: y - 21, width: sidebar.width - 8, height: 38), xRadius: 5, yRadius: 5).fill()
        }
        let name = file.0
        text(name, at: NSPoint(x: sidebar.minX + 12, y: y), size: 11, color: .white.withAlphaComponent(0.88))
        text(file.1, at: NSPoint(x: sidebar.minX + 12, y: y - 15), size: 9.5, color: .white.withAlphaComponent(0.42))
    }

    let body = NSRect(x: sidebar.maxX + 18, y: page.minY, width: page.maxX - sidebar.maxX - 22, height: page.height)
    guard m.note else {
        if m.shown == 0 {
            text("No notes yet", at: NSPoint(x: body.midX, y: body.midY + 6), size: 13, weight: .medium, color: .white.withAlphaComponent(0.4), centered: true)
        }
        return
    }
    var top = body.maxY - 18
    text("Reading List", at: NSPoint(x: body.minX, y: top), size: 16, weight: .bold)
    top -= 18
    text("8 unread · 6 read · from Safari", at: NSPoint(x: body.minX, y: top), size: 10.5, color: .white.withAlphaComponent(0.5))
    for (heading, pages, done) in [("Unread", unread, false), ("Read", finished, true)] {
        top -= 30
        text(heading, at: NSPoint(x: body.minX, y: top), size: 12, weight: .semibold)
        for page in pages {
            top -= 22
            checkbox(at: NSPoint(x: body.minX, y: top + 1), checked: done)
            text(page.0, at: NSPoint(x: body.minX + 20, y: top), size: 10.5, color: done ? ice.withAlphaComponent(0.6) : ice)
            top -= 13
            text(page.1, at: NSPoint(x: body.minX + 20, y: top), size: 9.5, color: .white.withAlphaComponent(0.42))
        }
    }
}

/// A task's box, as notes apps draw a Markdown checklist.
func checkbox(at point: NSPoint, checked: Bool) {
    let box = NSBezierPath(roundedRect: NSRect(x: point.x, y: point.y, width: 11, height: 11), xRadius: 3, yRadius: 3)
    if checked {
        ice.withAlphaComponent(0.8).setFill()
        box.fill()
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: point.x + 2.5, y: point.y + 5.5))
        tick.line(to: NSPoint(x: point.x + 4.8, y: point.y + 3))
        tick.line(to: NSPoint(x: point.x + 8.8, y: point.y + 8.2))
        tick.lineWidth = 1.6
        ink.setStroke()
        tick.stroke()
    } else {
        NSColor.white.withAlphaComponent(0.5).setStroke()
        box.lineWidth = 1
        box.stroke()
    }
}

func scene(_ m: Moment) {
    wallpaper(NSRect(x: 0, y: 0, width: width, height: height))
    notes(m)

    // The menu bar.
    NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.72).setFill()
    NSRect(x: 0, y: height - menuBarHeight, width: width, height: menuBarHeight).fill()
    text("Notebook", at: NSPoint(x: 18, y: height - 19), size: 12.5, weight: .bold)
    for (index, word) in ["File", "Edit", "View", "Window"].enumerated() {
        text(word, at: NSPoint(x: 96 + CGFloat(index) * 44, y: height - 19), size: 12.5)
    }
    if m.pressed || m.menuOpen {
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: iconCenter.x - 15, y: height - menuBarHeight + 3, width: 30, height: menuBarHeight - 6), xRadius: 5, yRadius: 5).fill()
    }
    statusIcon(at: iconCenter)
    for (index, name) in ["wifi", "magnifyingglass", "switch.2"].enumerated() {
        let image = symbol(name, size: 13, colors: [.white])
        image.draw(at: NSPoint(x: width - 128 + CGFloat(index) * 30, y: height - 20), from: .zero, operation: .sourceOver, fraction: 1)
    }
    text("9:41", at: NSPoint(x: width - 40, y: height - 19), size: 12.5, weight: .medium)

    if m.menuOpen { menu(hovering: m.hovering) }
    cursor(at: m.cursorAt, pressed: m.pressed)
}

/// The app's menu bar icon, drawn as in the app: a page with a ribbon and lines of text.
func statusIcon(at center: NSPoint) {
    NSColor.white.set()
    let page = NSRect(x: center.x - 5.5, y: center.y - 7, width: 11, height: 14)
    let outline = NSBezierPath(roundedRect: page, xRadius: 1.8, yRadius: 1.8)
    outline.lineWidth = 1.2
    outline.stroke()
    let ribbon = NSBezierPath()
    let left = page.minX + 2.4, right = left + 3.2, top = page.maxY
    ribbon.move(to: NSPoint(x: left, y: top))
    ribbon.line(to: NSPoint(x: right, y: top))
    ribbon.line(to: NSPoint(x: right, y: top - 6))
    ribbon.line(to: NSPoint(x: (left + right) / 2, y: top - 4.6))
    ribbon.line(to: NSPoint(x: left, y: top - 6))
    ribbon.close()
    ribbon.fill()
    for (index, length) in [5.0, 6.6, 4.2].enumerated() {
        let y = page.minY + 6.6 - CGFloat(index) * 2.4
        NSBezierPath(roundedRect: NSRect(x: page.minX + 2.4, y: y, width: length, height: 1.2), xRadius: 0.6, yRadius: 0.6).fill()
    }
}

func panel(_ rect: NSRect) {
    let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    body.lineWidth = 1
    body.stroke()
}

func separator(_ rect: NSRect, y: CGFloat) {
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSRect(x: rect.minX + 10, y: y, width: rect.width - 20, height: 1).fill()
}

let menuWidth: CGFloat = 280
let menuRect = NSRect(x: width - 8 - menuWidth, y: height - menuBarHeight - 4 - 222, width: menuWidth, height: 222)
let exportRowY = menuRect.maxY - 76

/// The app's menu, drawn as it looks open.
func menu(hovering: Bool) {
    panel(menuRect)
    let left = menuRect.minX + 14
    var y = menuRect.maxY - 26
    text("8 unread · 6 read", at: NSPoint(x: left, y: y), size: 13, color: .white.withAlphaComponent(0.5))
    y -= 17
    text("Choose a folder to start exporting", at: NSPoint(x: left, y: y), size: 11, color: .white.withAlphaComponent(0.4))
    separator(menuRect, y: y - 10)
    let row = NSRect(x: menuRect.minX + 6, y: exportRowY - 5, width: menuRect.width - 12, height: 24)
    if hovering {
        NSColor.systemBlue.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: row, xRadius: 6, yRadius: 6).fill()
    }
    text("Export 14 New Pages", at: NSPoint(x: left, y: exportRowY), size: 13, weight: hovering ? .medium : .regular)
    text("⌘E", at: NSPoint(x: menuRect.maxX - 38, y: exportRowY), size: 13, color: .white.withAlphaComponent(hovering ? 0.9 : 0.5))
    y = exportRowY
    for line in ["Export Folder: ~/Vault/Reading", "Save as Bookmarks File…", "Open Reading List Export…"] {
        y -= 24
        text(line, at: NSPoint(x: left, y: y), size: 13)
        if line.hasPrefix("Export Folder") {
            text("›", at: NSPoint(x: menuRect.maxX - 22, y: y), size: 13, color: .white.withAlphaComponent(0.5))
        } else {
            text(line.hasPrefix("Save") ? "⌘S" : "⌘O", at: NSPoint(x: menuRect.maxX - 38, y: y), size: 13, color: .white.withAlphaComponent(0.5))
        }
    }
    separator(menuRect, y: y - 12)
    y -= 36
    text("Export Options", at: NSPoint(x: left, y: y), size: 13)
    text("›", at: NSPoint(x: menuRect.maxX - 22, y: y), size: 13, color: .white.withAlphaComponent(0.5))
    y -= 24
    text("Export Automatically", at: NSPoint(x: left, y: y), size: 13)
}

// MARK: Demo

func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    let e = t * t * (3 - 2 * t)
    return NSPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
}

var frames: [(NSBitmapImageRep, Double)] = []
func frame(_ m: Moment, hold: Double = 0.07) {
    // Drawn at 2x so the GIF looks sharp on Retina screens when shown at 720 points.
    let rep = bitmap(Int(width * 2), Int(height * 2)) {
        let transform = NSAffineTransform()
        transform.scale(by: 2)
        transform.concat()
        scene(m)
    }
    frames.append((rep, hold))
}

var m = Moment()
frame(m, hold: 0.9)
// 14 pages waiting. Export them from the menu bar.
let onIcon = NSPoint(x: iconCenter.x - 2, y: iconCenter.y + 6)
let start = m.cursorAt
for step in 1...12 {
    m.cursorAt = lerp(start, onIcon, CGFloat(step) / 12)
    frame(m, hold: 0.04)
}
m.pressed = true
frame(m, hold: 0.12)
m.pressed = false
m.menuOpen = true
frame(m, hold: 0.9)
let onExport = NSPoint(x: menuRect.minX + 80, y: exportRowY + 8)
let fromIcon = m.cursorAt
for step in 1...10 {
    m.cursorAt = lerp(fromIcon, onExport, CGFloat(step) / 10)
    frame(m, hold: 0.04)
}
m.hovering = true
frame(m, hold: 0.7)
m.pressed = true
frame(m, hold: 0.1)
m.pressed = false
m.menuOpen = false
m.hovering = false
// The note, the bookmarks file and the CSV land in the folder.
for count in 1...files.count {
    m.shown = count
    frame(m, hold: 0.28)
}
frame(m, hold: 0.5)
// And the note has every page, unread first, read ones checked off.
let fromMenu = m.cursorAt
let onNote = NSPoint(x: notesFrame.minX + 176, y: notesFrame.maxY - 92)
for step in 1...12 {
    m.cursorAt = lerp(fromMenu, onNote, CGFloat(step) / 12)
    frame(m, hold: 0.04)
}
m.note = true
frame(m, hold: 4.2)

let gifURL = URL(fileURLWithPath: "docs/demo.gif")
let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (rep, hold) in frames {
    CGImageDestinationAddImage(destination, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: hold]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write the GIF") }

// The last frame on its own, for checking the art without playing the GIF.
if let preview = ProcessInfo.processInfo.environment["PREVIEW"] {
    try frames.last!.0.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}

// MARK: Link preview

let social = bitmap(1280, 640) {
    let rect = NSRect(x: 0, y: 0, width: 1280, height: 640)
    wallpaper(rect)
    if let icon = NSImage(contentsOfFile: "docs/icon.png") {
        icon.draw(in: NSRect(x: 640 - 80, y: 380, width: 160, height: 160))
    }
    text("Reading List Export", at: NSPoint(x: 640, y: 270), size: 84, weight: .semibold, centered: true)
    text("Your Safari Reading List as Markdown, bookmarks and CSV.", at: NSPoint(x: 640, y: 205), size: 30, color: .white.withAlphaComponent(0.75), centered: true)
    text("free · open source · read-only · no internet access", at: NSPoint(x: 640, y: 120), size: 22, weight: .medium, color: .white.withAlphaComponent(0.5), centered: true)
}
try social.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
print("Wrote docs/demo.gif and docs/social.png")
