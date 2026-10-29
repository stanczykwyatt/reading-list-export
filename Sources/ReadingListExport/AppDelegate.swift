import AppKit
import ReadingListCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, StatusMenuActions {
    private let preferences = Preferences()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private lazy var model = ReadingModel(source: SafariBookmarks(home: SafariBookmarks.realHome), preferences: preferences)
    private lazy var statusMenu = StatusMenu(model: model, actions: self)
    private lazy var window = ReadingWindowController { [unowned self] in
        ReadingView(
            model: model,
            export: { [unowned self] in exportNow() },
            chooseFolder: { [unowned self] in chooseFolder() },
            openPrivacySettings: { [unowned self] in openPrivacySettings() }
        )
    }

    /// How often to look for new pages. Looking is one file date unless something changed, and the
    /// export doesn't need to be fresher than this.
    static let checkInterval: TimeInterval = 10 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()

        // Gives the keyboard back to the app you were using.
        window.onClose = { NSApp.hide(nil) }
        // Coming back from System Settings after turning on access, or from Safari.
        window.onActivate = { [weak self] in self?.check() }

        check()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // The first time, open at login like most menu bar utilities, and show the window so it's
        // clear what the app does and whether it needs Full Disk Access. Turn off login in the menu.
        if !preferences.launchedBefore {
            preferences.launchedBefore = true
            try? SMAppService.mainApp.register()
            openWindow()
        }
    }

    /// Reads the Reading List if it changed, then exports if that's turned on.
    private func check(force: Bool = false) {
        Task {
            let changed = await model.reload(force: force || model.status != .ready)
            if preferences.exportsAutomatically, model.folder != nil, changed || force {
                await model.export()
            }
            updateStatusItem()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let attention = model.status == .problem(.noPermission) || model.exportProblem != nil || !model.failures.isEmpty
        button.image = StatusIcon.image(alert: attention)
        var tip = "Reading List Export"
        if model.status == .ready {
            tip += "\n" + Describe.totals(model.list) + "."
            if model.pending > 0 { tip += "\n\(Describe.count(model.pending, "new page")) to export." }
        } else if case .problem(let error) = model.status {
            tip += "\n" + Describe.problem(error)
        }
        button.toolTip = tip
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusMenu.build(into: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        check()
    }

    // MARK: StatusMenuActions

    func exportNow() {
        guard model.folder != nil else {
            chooseFolder()
            return
        }
        Task {
            await model.reload()
            await model.export()
            updateStatusItem()
        }
    }

    func chooseFolder() {
        // Changing folders partway through an export would leave it half in each.
        guard !model.isExporting else { return }
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Choose Where to Export Your Reading List"
        panel.message = "Your Reading List is saved here as Markdown, a bookmarks file and a CSV. A folder in your Obsidian vault works well."
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.folder?.url ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            if model.source.protectedFolders.contains(where: { Exporter.isInside(url, $0) }) {
                refuseSafariFolder()
            } else {
                Task {
                    await model.setFolder(url)
                    exportNow()
                }
            }
        }
        if !window.isVisible {
            NSApp.hide(nil)
        }
    }

    func saveBookmarks() {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.title = "Save Reading List as a Bookmarks File"
        panel.message = "Import this file into Linkding, Karakeep, Raindrop.io or a browser to bring your Reading List along."
        panel.nameFieldStringValue = "Reading List.html"
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            if model.source.protectedFolders.contains(where: { Exporter.isInside(url, $0) }) {
                refuseSafariFolder()
            } else if let problem = model.saveBookmarks(to: url) {
                let alert = NSAlert()
                alert.messageText = "Couldn't save the bookmarks file"
                alert.informativeText = problem
                alert.runModal()
            }
        }
        if !window.isVisible {
            NSApp.hide(nil)
        }
    }

    private func refuseSafariFolder() {
        let alert = NSAlert()
        alert.messageText = "Choose a folder outside Safari's"
        alert.informativeText = "Reading List Export never writes inside Safari's folder."
        alert.runModal()
    }

    func showFolder() {
        guard let url = model.folder?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openWindow() {
        window.show()
    }

    func copyLink(_ id: String) {
        if let item = model.list.item(id) { model.copy([item]) }
    }

    func openPrivacySettings() {
        // The one page the app ever opens: where you turn on Full Disk Access.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    func toggleOpenAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    func optionsChanged() {
        // New options can mean files to write that weren't before.
        check(force: preferences.exportsAutomatically)
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Free and open source. No internet access.\ngithub.com/stanczykwyatt/reading-list-export",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
}
