import AppKit
import ReadingListCore
import ServiceManagement

/// What the menu's items do. The app delegate does them; tests record them.
@MainActor
protocol StatusMenuActions: AnyObject {
    func exportNow()
    func chooseFolder()
    func showFolder()
    func saveBookmarks()
    func openWindow()
    func copyLink(_ id: String)
    func openPrivacySettings()
    func toggleOpenAtLogin()
    func optionsChanged()
    func showAbout()
}

/// Builds the menu bar menu fresh each time it opens.
@MainActor
final class StatusMenu: NSObject {
    private let model: ReadingModel
    private weak var actions: StatusMenuActions?
    var now: () -> Date = Date.init
    var opensAtLogin: () -> Bool = { SMAppService.mainApp.status == .enabled }
    var home = SafariBookmarks.realHome

    static let recentLimit = 8

    init(model: ReadingModel, actions: StatusMenuActions) {
        self.model = model
        self.actions = actions
    }

    func build(into menu: NSMenu) {
        menu.removeAllItems()
        switch model.status {
        case .loading:
            menu.addItem(disabled("Reading Safari…"))
        case .problem(.noPermission):
            menu.addItem(disabled("Needs Full Disk Access"))
            menu.addItem(disabled("Turn on Reading List Export in Full Disk Access to read your Reading List. It can still only read Safari's bookmarks file.", small: true))
            menu.addItem(item("Open Privacy & Security Settings…", #selector(openPrivacySettings)))
        case .problem(let error):
            menu.addItem(disabled("Can't read Safari's Reading List"))
            menu.addItem(disabled(Describe.problem(error), small: true))
        case .ready:
            menu.addItem(disabled(Describe.totals(model.list)))
            if model.list.skipped > 0 {
                menu.addItem(disabled("Left out \(Describe.skipped(model.list.skipped)).", small: true))
            }
            if let last = model.lastExport {
                menu.addItem(disabled("Last export \(Describe.relative(last.date, now: now())): \(last.summary.prefix(1).lowercased() + last.summary.dropFirst())", small: true))
            }
        }
        if let problem = model.exportProblem {
            menu.addItem(disabled(problem, small: true, warning: true))
        } else if !model.failures.isEmpty {
            let names = model.failures.prefix(3).map(\.file).joined(separator: ", ")
            menu.addItem(disabled("Couldn't write \(names)\(model.failures.count > 3 ? " and \(model.failures.count - 3) more" : ""). \(model.failures[0].reason)", small: true, warning: true))
        } else if model.heldBack {
            menu.addItem(disabled("Safari lists far fewer pages than last time, as it can while iCloud syncs, so none were marked removed. If you cleared them, they're marked after a day.", small: true))
        } else if !model.kept.isEmpty {
            let names = model.kept.prefix(2).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            menu.addItem(disabled("Left \(names)\(model.kept.count > 2 ? " and \(model.kept.count - 2) more" : "") as you edited \(model.kept.count == 1 ? "it" : "them").", small: true))
        }
        menu.addItem(.separator())

        let ready = model.status == .ready && !model.isExporting
        if model.folder == nil {
            let choose = item("Choose Export Folder…", #selector(chooseFolder), key: "e")
            choose.isEnabled = ready
            menu.addItem(choose)
        } else {
            let title = model.isExporting ? "Exporting…" : model.pending > 0 ? "Export \(Describe.count(model.pending, "New Page"))" : "Export Now"
            let export = item(title, #selector(exportNow), key: "e")
            export.isEnabled = ready
            menu.addItem(export)
            menu.addItem(folderItem())
        }
        let save = item("Save as Bookmarks File…", #selector(saveBookmarks), key: "s")
        save.isEnabled = model.status == .ready && !model.list.items.isEmpty
        save.toolTip = "Saves your Reading List as one HTML bookmarks file, to import into Linkding, Karakeep, Raindrop.io or a browser."
        menu.addItem(save)
        menu.addItem(item("Open Reading List Export…", #selector(openWindow), key: "o"))
        menu.addItem(recentItem())

        menu.addItem(.separator())
        menu.addItem(optionsItem())
        let automatic = item("Export Automatically", #selector(toggleAutomatic))
        automatic.state = model.preferences.exportsAutomatically ? .on : .off
        automatic.toolTip = "Exports new pages within about ten minutes of saving them, and whenever you open this menu, while Reading List Export is running."
        menu.addItem(automatic)
        let login = item("Open at Login", #selector(toggleOpenAtLogin))
        login.state = opensAtLogin() ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("About Reading List Export", #selector(showAbout)))
        let quit = NSMenuItem(title: "Quit Reading List Export", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: Parts

    private func folderItem() -> NSMenuItem {
        let path = model.folder.map { Describe.path($0.url, home: home) } ?? ""
        let item = NSMenuItem(title: "Export Folder: \(path)", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.addItem(self.item("Show in Finder", #selector(showFolder)))
        let change = self.item("Choose Another Folder…", #selector(chooseFolder))
        change.isEnabled = !model.isExporting
        submenu.addItem(change)
        item.submenu = submenu
        return item
    }

    private func recentItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Recently Added", action: nil, keyEquivalent: "")
        let recent = model.list.items.prefix(Self.recentLimit)
        item.isEnabled = !recent.isEmpty
        let submenu = NSMenu()
        submenu.addItem(disabled("Click to copy the link", small: true))
        for page in recent {
            var detail = [page.site]
            if let added = page.added { detail.append(Describe.relative(added, now: now())) }
            detail.append(page.read ? "read" : "unread")
            let entry = twoLine(String(page.title.prefix(70)), detail.filter { !$0.isEmpty }.joined(separator: " · "), #selector(copyLink(_:)))
            entry.representedObject = page.id
            entry.image = NSImage(systemSymbolName: page.read ? "checkmark.circle" : "circle", accessibilityDescription: nil)
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private func optionsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Export Options", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let preferences = model.preferences
        let options: [(String, Bool, Selector, String)] = [
            ("Markdown Note (.md)", preferences.writesMarkdown, #selector(toggleMarkdown), "Reading List.md: unread pages as tasks, read ones checked off. Works in Obsidian."),
            ("Bookmarks File (.html)", preferences.writesBookmarks, #selector(toggleBookmarks), "Reading List.html, for Linkding, Karakeep, Raindrop.io and browsers."),
            ("Instapaper CSV (.csv)", preferences.writesCSV, #selector(toggleCSV), "Reading List.csv in Instapaper's layout, for Wallabag and Readwise Reader, or a spreadsheet."),
            ("JSON (.json)", preferences.writesJSON, #selector(toggleJSON), "Every page with everything known about it, for scripts."),
            ("A Note for Each Page", preferences.writesNotes, #selector(toggleNotes), "One Markdown note per page in a Pages folder. Notes you delete stay deleted."),
        ]
        for (title, on, action, tip) in options {
            let option = self.item(title, action)
            option.state = on ? .on : .off
            option.toolTip = tip
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func twoLine(_ title: String, _ detail: String, _ action: Selector) -> NSMenuItem {
        let item = self.item(title, action)
        let text = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(string: "\n" + detail, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        item.attributedTitle = text
        return item
    }

    private func disabled(_ title: String, small: Bool = false, warning: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if small || warning {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: warning ? NSColor.systemOrange : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
            if title.count > 44 { item.view = wrapping(item.attributedTitle!) }
        }
        return item
    }

    /// Long notes in the menu wrap instead of making it as wide as the screen.
    private func wrapping(_ text: NSAttributedString) -> NSView {
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text
        label.preferredMaxLayoutWidth = 270
        label.frame.size = label.fittingSize
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: label.frame.height + 6))
        label.frame.origin = NSPoint(x: 14, y: 3)
        view.addSubview(label)
        return view
    }

    // MARK: Actions

    @objc private func exportNow() { actions?.exportNow() }
    @objc private func chooseFolder() { actions?.chooseFolder() }
    @objc private func showFolder() { actions?.showFolder() }
    @objc private func saveBookmarks() { actions?.saveBookmarks() }
    @objc private func openWindow() { actions?.openWindow() }
    @objc private func copyLink(_ sender: NSMenuItem) { (sender.representedObject as? String).map { actions?.copyLink($0) } }
    @objc private func openPrivacySettings() { actions?.openPrivacySettings() }
    @objc private func toggleOpenAtLogin() { actions?.toggleOpenAtLogin() }
    @objc private func showAbout() { actions?.showAbout() }

    @objc private func toggleAutomatic() {
        model.preferences.exportsAutomatically.toggle()
        actions?.optionsChanged()
    }

    @objc private func toggleMarkdown() {
        model.preferences.writesMarkdown.toggle()
        actions?.optionsChanged()
    }

    @objc private func toggleBookmarks() {
        model.preferences.writesBookmarks.toggle()
        actions?.optionsChanged()
    }

    @objc private func toggleCSV() {
        model.preferences.writesCSV.toggle()
        actions?.optionsChanged()
    }

    @objc private func toggleJSON() {
        model.preferences.writesJSON.toggle()
        actions?.optionsChanged()
    }

    @objc private func toggleNotes() {
        model.preferences.writesNotes.toggle()
        actions?.optionsChanged()
    }
}
