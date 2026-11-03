import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ReadingListCore
@testable import ReadingListExport

/// Renders the window into a bitmap from a window that's never shown, so nothing appears on screen
/// or takes focus. Set SCREENSHOT_DIR to also save the renders as the README screenshots:
///
///   SCREENSHOT_DIR=docs swift test --filter "Window"
@MainActor
@Suite("Window")
struct WindowTests {
    let folder = TestFolder()
    static let size = NSSize(width: 940, height: 620)

    private func view(_ model: ReadingModel, query: String = "", filter: Search.Filter = .all) -> ReadingView {
        ReadingView(
            model: model, home: folder.url, now: { Gallery.now }, tint: Color(red: 0.24, green: 0.47, blue: 0.86),
            renderer: Renderer(timeZone: TimeZone(identifier: "America/Chicago")!, locale: Locale(identifier: "en_US")),
            query: query, filter: filter
        )
    }

    @Test func rendersTheReadingList() async throws {
        let model = try await Gallery.model(in: folder, exportTo: folder.sub("Vault/Reading"))
        model.preferences.lastExport = (Gallery.now.addingTimeInterval(-60 * 90), "Added 3 new pages")
        let image = render(view(model), name: "screenshot-light", dark: false)
        #expect(image.pixelsWide >= Int(Self.size.width))
        #expect(colors(in: image) > 20)
    }

    @Test func rendersInDarkMode() async throws {
        let model = try await Gallery.model(in: folder, exportTo: folder.sub("Vault/Reading"))
        model.preferences.lastExport = (Gallery.now.addingTimeInterval(-60 * 90), "Added 3 new pages")
        #expect(colors(in: render(view(model), name: "screenshot-dark", dark: true)) > 20)
    }

    @Test func rendersASearch() async throws {
        let model = try await Gallery.model(in: folder, exportTo: folder.sub("Vault/Reading"))
        #expect(colors(in: render(view(model, query: "how", filter: .unread), name: "screenshot-search", dark: false)) > 30)
    }

    @Test func rendersTheOtherStates() async throws {
        let missing = ReadingModel(source: SafariBookmarks(home: folder.sub("none")), preferences: testPreferences())
        #expect(colors(in: render(view(missing), name: nil, dark: false)) > 4)
        await missing.reload()
        #expect(colors(in: render(view(missing), name: nil, dark: true)) > 4)
        let model = try await Gallery.model(in: folder)
        #expect(colors(in: render(view(model, filter: .read), name: nil, dark: false)) > 4)
        #expect(colors(in: render(view(model, query: "nothing like this"), name: nil, dark: true)) > 4)
    }

    @Test func rendersTheAccessPrompt() async throws {
        let home = folder.sub("Locked")
        try Gallery.write(to: home)
        let file = SafariBookmarks(home: home).file
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let model = ReadingModel(source: SafariBookmarks(home: home), preferences: testPreferences())
        await model.reload()
        #expect(colors(in: render(view(model), name: "screenshot-access", dark: false, size: NSSize(width: 820, height: 440))) > 8)
    }

    @Test func everySymbolExists() {
        for symbol in ["magnifyingglass", "xmark.circle.fill", "checkmark.circle", "circle.fill", "circle", "circle.dashed", "lock.shield",
                       "text.badge.plus", "exclamationmark.circle", "folder", "folder.badge.plus", "exclamationmark.triangle.fill"] {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing symbol \(symbol)")
        }
    }

    @Test func theMenuBarIconIsATemplate() {
        for alert in [false, true] {
            let image = StatusIcon.image(alert: alert)
            #expect(image.isTemplate && image.size == NSSize(width: 18, height: 18))
            #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
        }
    }

    // MARK: Rendering

    private func render(_ view: ReadingView, name: String?, dark: Bool, size: NSSize = WindowTests.size) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Never ordered front: it only gives the view a backing to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        if let name, let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? image.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    /// Distinct colors in a coarse grid: a blank or broken render has only a few.
    private func colors(in image: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: image.pixelsWide, by: 7) {
            for y in stride(from: 0, to: image.pixelsHigh, by: 7) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = UInt32(color.redComponent * 31), g = UInt32(color.greenComponent * 31), b = UInt32(color.blueComponent * 31)
                seen.insert(r << 10 | g << 5 | b)
            }
        }
        return seen.count
    }
}

/// The app's entitlements, checked against what the code expects.
@Suite("Entitlements")
struct EntitlementTests {
    static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/ReadingListExport.entitlements")

    @Test func onlyTheSandboxTheBookmarksFileAndYourFolder() throws {
        let entitlements = try #require(NSDictionary(contentsOf: Self.file) as? [String: Any])
        #expect(Set(entitlements.keys) == [
            "com.apple.security.app-sandbox",
            "com.apple.security.temporary-exception.files.home-relative-path.read-only",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.files.bookmarks.app-scope",
        ])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        let readOnly = entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String]
        // The one file, not Safari's whole folder.
        #expect(readOnly == ["/" + SafariBookmarks.relativePath])
    }
}
