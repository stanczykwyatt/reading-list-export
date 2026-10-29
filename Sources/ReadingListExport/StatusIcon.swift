import AppKit

/// The menu bar icon: a page with a ribbon marking your place, and lines of text below it.
enum StatusIcon {
    static func image(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            let shift: CGFloat = alert ? -1.5 : 0
            let page = NSRect(x: 3 + shift, y: 2, width: 11, height: 14)
            let outline = NSBezierPath(roundedRect: page, xRadius: 1.8, yRadius: 1.8)
            outline.lineWidth = 1.2
            outline.stroke()
            // The ribbon hangs from the top edge, with a notch cut into its end.
            let ribbon = NSBezierPath()
            let left = page.minX + 2.4, right = left + 3.2, top = page.maxY
            ribbon.move(to: NSPoint(x: left, y: top))
            ribbon.line(to: NSPoint(x: right, y: top))
            ribbon.line(to: NSPoint(x: right, y: top - 6))
            ribbon.line(to: NSPoint(x: (left + right) / 2, y: top - 4.6))
            ribbon.line(to: NSPoint(x: left, y: top - 6))
            ribbon.close()
            ribbon.fill()
            for (index, width) in [5.0, 6.6, 4.2].enumerated() {
                let y = page.minY + 6.6 - CGFloat(index) * 2.4
                NSBezierPath(roundedRect: NSRect(x: page.minX + 2.4, y: y, width: width, height: 1.2), xRadius: 0.6, yRadius: 0.6).fill()
            }
            if alert {
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = alert ? "Reading List Export, needs attention" : "Reading List Export"
        return image
    }
}
