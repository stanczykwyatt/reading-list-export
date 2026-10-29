import AppKit
import Foundation
import Testing
@testable import ReadingListCore
@testable import ReadingListExport

@MainActor
final class RecordedActions: StatusMenuActions {
    var calls: [String] = []
    func exportNow() { calls.append("export") }
    func chooseFolder() { calls.append("choose") }
    func showFolder() { calls.append("show") }
    func saveBookmarks() { calls.append("bookmarks") }
    func openWindow() { calls.append("window") }
    func copyLink(_ id: String) { calls.append("copy:\(id)") }
    func openPrivacySettings() { calls.append("privacy") }
    func toggleOpenAtLogin() { calls.append("login") }
    func optionsChanged() { calls.append("options") }
    func showAbout() { calls.append("about") }
}

/// The menu, built into an NSMenu that's never shown.
@MainActor
@Suite("Menu")
struct StatusMenuTests {
    let folder = TestFolder()
    let actions = RecordedActions()

    private func build(_ model: ReadingModel) -> NSMenu {
        let statusMenu = StatusMenu(model: model, actions: actions)
        statusMenu.now = { Gallery.now }
        statusMenu.opensAtLogin = { true }
        statusMenu.home = folder.url
        let menu = NSMenu()
        statusMenu.build(into: menu)
        // Keeps the builder alive for the menu's targets, as the app delegate does.
        objc_setAssociatedObject(menu, "builder", statusMenu, .OBJC_ASSOCIATION_RETAIN)
        return menu
    }

    private func titles(_ menu: NSMenu?) -> [String] {
        menu?.items.map { $0.isSeparatorItem ? "—" : ($0.attributedTitle?.string ?? $0.title) } ?? []
    }

    private func item(_ menu: NSMenu?, _ title: String) throws -> NSMenuItem {
        try #require(menu?.items.first { ($0.attributedTitle?.string ?? $0.title).components(separatedBy: "\n")[0] == title }, "No item titled \(title)")
    }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    @Test func beforeChoosingAFolder() async throws {
        let menu = build(try await Gallery.model(in: folder))
        #expect(titles(menu).first == "8 unread · 6 read")
        let choose = try item(menu, "Choose Export Folder…")
        #expect(choose.isEnabled && choose.keyEquivalent == "e")
        click(choose)
        #expect(actions.calls == ["choose"])
        #expect(!titles(menu).contains { $0.hasPrefix("Export Folder") })
    }

    @Test func withAFolder() async throws {
        let model = try await Gallery.model(in: folder, exportTo: folder.sub("Notes/Reading"))
        let menu = build(model)
        let export = try item(menu, "Export 14 New Pages")
        #expect(export.isEnabled)
        click(export)
        let folderItem = try item(menu, "Export Folder: ~/Notes/Reading")
        click(try item(folderItem.submenu, "Show in Finder"))
        click(try item(folderItem.submenu, "Choose Another Folder…"))
        #expect(actions.calls == ["export", "show", "choose"])
        await model.export(now: Gallery.now)
        let after = build(model)
        #expect(try item(after, "Export Now").isEnabled)
        #expect(titles(after).contains("Last export just now: added 14 new pages"))
    }

    @Test func recentlyAddedCopiesALink() async throws {
        let menu = build(try await Gallery.model(in: folder))
        let recent = try item(menu, "Recently Added")
        #expect(recent.isEnabled)
        let entries = recent.submenu!.items.dropFirst()
        #expect(entries.count == StatusMenu.recentLimit)
        let first = try #require(entries.first)
        #expect(first.attributedTitle?.string == "How tide pools survive the winter\nTide Watch · 4 hr ago · unread")
        click(first)
        #expect(actions.calls == ["copy:PAGE-0"])
    }

    @Test func everyOtherItemDoesWhatItSays() async throws {
        let menu = build(try await Gallery.model(in: folder))
        for (title, call) in [("Save as Bookmarks File…", "bookmarks"), ("Open Reading List Export…", "window"), ("Open at Login", "login"), ("About Reading List Export", "about")] {
            click(try item(menu, title))
            #expect(actions.calls.last == call)
        }
        #expect(try item(menu, "Open at Login").state == .on)
        #expect(try item(menu, "Quit Reading List Export").action == #selector(NSApplication.terminate(_:)))
    }

    @Test func optionsToggle() async throws {
        let model = try await Gallery.model(in: folder)
        let menu = build(model)
        let options = try item(menu, "Export Options").submenu
        #expect(titles(options) == ["Markdown Note (.md)", "Bookmarks File (.html)", "Instapaper CSV (.csv)", "JSON (.json)", "A Note for Each Page"])
        #expect(options?.items.map(\.state) == [.on, .on, .on, .off, .off])
        for entry in options?.items ?? [] { click(entry) }
        #expect(model.preferences.options == ExportOptions(markdown: false, bookmarks: false, csv: false, json: true, notes: true))
        #expect(actions.calls == Array(repeating: "options", count: 5))
        click(try item(menu, "Export Automatically"))
        #expect(model.preferences.exportsAutomatically)
    }

    @Test func askingForAccess() async throws {
        let home = folder.sub("Locked")
        try Gallery.write(to: home)
        let file = SafariBookmarks(home: home).file
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let model = ReadingModel(source: SafariBookmarks(home: home), preferences: testPreferences())
        await model.reload()
        let menu = build(model)
        #expect(titles(menu).first == "Needs Full Disk Access")
        click(try item(menu, "Open Privacy & Security Settings…"))
        #expect(actions.calls == ["privacy"])
        #expect(try item(menu, "Choose Export Folder…").isEnabled == false)
        #expect(try item(menu, "Save as Bookmarks File…").isEnabled == false)
    }

    @Test func whileLoadingAndWhenEmpty() async throws {
        let loading = ReadingModel(source: SafariBookmarks(home: folder.sub("Nothing")), preferences: testPreferences())
        #expect(titles(build(loading)).first == "Reading Safari…")
        await loading.reload()
        #expect(titles(build(loading)).first == "Can't read Safari's Reading List")
        let home = folder.sub("EmptyHome")
        let safari = home.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        let root: [String: Any] = ["Children": [["Title": "com.apple.ReadingList", "Children": []]]]
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: safari.appendingPathComponent("Bookmarks.plist"))
        let empty = ReadingModel(source: SafariBookmarks(home: home), preferences: testPreferences())
        await empty.reload()
        let menu = build(empty)
        #expect(titles(menu).first == "Reading List is empty")
        #expect(try item(menu, "Recently Added").isEnabled == false)
    }

    @Test func saysWhenRemovalsAreHeldBack() async throws {
        let destination = folder.sub("Held")
        let model = try await Gallery.model(in: folder, exportTo: destination)
        await model.export(now: Gallery.now)
        // Safari now lists none of the pages, as it can mid-sync.
        let root: [String: Any] = ["Children": [["Title": "com.apple.ReadingList", "Children": []]]]
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: model.source.file)
        await model.reload(force: true)
        await model.export(now: Gallery.now)
        #expect(model.heldBack)
        let menu = build(model)
        #expect(menu.items.contains { ($0.view?.subviews.first as? NSTextField)?.stringValue.contains("none were marked removed") == true })
    }

    @Test func showsExportProblems() async throws {
        let destination = folder.sub("Damaged")
        try Data("nope".utf8).write(to: destination.appendingPathComponent(Exporter.recordName))
        let model = try await Gallery.model(in: folder, exportTo: destination)
        let menu = build(model)
        #expect(menu.items.contains { ($0.view?.subviews.first as? NSTextField)?.stringValue.contains("can't be read") == true })
    }
}
