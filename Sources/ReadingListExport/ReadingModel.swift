import AppKit
import Observation
import ReadingListCore

/// What the app knows about your Reading List, shared by the menu and the window. The bookmarks
/// file is read off the main thread, and only again once Safari has changed it.
@MainActor
@Observable
final class ReadingModel {
    enum Status: Equatable {
        case loading
        case ready
        case problem(LibraryError)
    }

    private(set) var status: Status = .loading
    private(set) var list = ReadingList()
    /// Pages that aren't in the export folder yet.
    private(set) var pending = 0
    private(set) var isExporting = false
    /// Why the last export stopped, if it did.
    private(set) var exportProblem: String?
    private(set) var failures: [ExportReport.Failure] = []
    /// Files you've edited that the last export left alone.
    private(set) var kept: [String] = []
    /// The last export found far fewer pages in Safari than before, so it marked none removed yet.
    private(set) var heldBack = false
    private(set) var folder: ExportFolder?

    /// Called after each export with what it did.
    var onExport: ((ExportReport) -> Void)?

    let source: SafariBookmarks
    let preferences: Preferences
    private var lastChange: SafariBookmarks.Stamp?
    private var loading: Task<Void, Never>?
    /// Asked to export while one was running, so another runs once it's done, with what changed.
    private var exportAgain = false
    /// Counts each count of what's new, so one that finishes late never replaces a newer one.
    private var pendingGeneration = 0

    init(source: SafariBookmarks, preferences: Preferences, folder: ExportFolder? = nil) {
        self.source = source
        self.preferences = preferences
        if let folder {
            self.folder = folder
        } else if let bookmark = preferences.folderBookmark, let resolved = ExportFolder.resolve(bookmark) {
            self.folder = resolved.folder
            if let refreshed = resolved.refreshed { preferences.folderBookmark = refreshed }
        }
    }

    var lastExport: (date: Date, summary: String)? { preferences.lastExport }

    // MARK: Reading

    /// Reads the Reading List again if Safari has changed it since last time, or `force` is set.
    /// Returns whether it was read.
    @discardableResult
    func reload(force: Bool = false) async -> Bool {
        while let loading {
            await loading.value
            if !force { return false }
        }
        let change = source.lastChange()
        // With no date to go by, it's read each time; a bookmarks file is quick to read.
        if !force, status == .ready, let change, change == lastChange { return false }
        // The task clears itself before it finishes, so anyone waiting on it finds it gone and
        // never waits on a finished task again.
        let task = Task {
            await read(change: change)
            loading = nil
        }
        loading = task
        await task.value
        return true
    }

    private func read(change: SafariBookmarks.Stamp?) async {
        let source = source
        let result = await Task.detached(priority: .utility) { () -> Result<ReadingList, LibraryError> in
            do {
                return .success(try source.read())
            } catch let error as LibraryError {
                return .failure(error)
            } catch {
                return .failure(.unrecognized(error.localizedDescription))
            }
        }.value
        switch result {
        case .success(let list):
            self.list = list
            status = .ready
            lastChange = change
        case .failure(let error):
            status = .problem(error)
            lastChange = nil
        }
        await refreshPending()
    }

    /// Counts what's new against the export record, off the main thread, since a long list makes
    /// for a big record.
    private func refreshPending() async {
        pendingGeneration += 1
        let generation = pendingGeneration
        guard let folder, status == .ready else {
            pending = 0
            return
        }
        let list = list
        let result = await Task.detached(priority: .utility) { () -> Result<Int, ExportError> in
            folder.access { url in
                do {
                    return .success(try Exporter(destination: url).newItems(list))
                } catch let error as ExportError {
                    return .failure(error)
                } catch {
                    return .failure(.cannotWrite(error.localizedDescription))
                }
            }
        }.value
        // A newer count, after an export or a change of folder, already has the answer.
        guard generation == pendingGeneration else { return }
        switch result {
        case .success(let count):
            pending = count
        case .failure(let error):
            pending = 0
            exportProblem = Describe.problem(error)
        }
    }

    // MARK: Exporting

    func setFolder(_ url: URL) async {
        exportProblem = nil
        failures = []
        kept = []
        folder = ExportFolder(url: url, scoped: false)
        // Reopened from the bookmark, so later exports work after a relaunch the same way.
        if let bookmark = ExportFolder.bookmark(for: url), let resolved = ExportFolder.resolve(bookmark) {
            preferences.folderBookmark = bookmark
            folder = resolved.folder
        } else {
            exportProblem = "macOS didn't let Reading List Export remember this folder, so you'll need to choose it again after Reading List Export quits."
        }
        await refreshPending()
    }

    /// Exports what's new into the folder. Returns nil if there's no folder, the Reading List can't
    /// be read, or an export is already running, in which case another runs once it's done.
    @discardableResult
    func export(now: Date? = nil) async -> ExportReport? {
        if isExporting {
            exportAgain = true
            return nil
        }
        guard let folder, status == .ready else { return nil }
        let now = now ?? Date()
        isExporting = true
        exportProblem = nil
        failures = []
        let list = list, options = preferences.options, protected = source.protectedFolders
        let result = await Task.detached(priority: .utility) { () -> Result<ExportReport, ExportError> in
            folder.access { url in
                do {
                    return .success(try Exporter(destination: url, options: options).export(list, protected: protected, now: now))
                } catch let error as ExportError {
                    return .failure(error)
                } catch {
                    return .failure(.cannotWrite(error.localizedDescription))
                }
            }
        }.value
        isExporting = false
        await refreshPending()
        if exportAgain {
            exportAgain = false
            Task { await self.export() }
        }
        switch result {
        case .success(let report):
            failures = report.failed
            kept = report.kept
            heldBack = report.heldBack
            preferences.lastExport = (now, Describe.summary(report))
            onExport?(report)
            return report
        case .failure(let error):
            exportProblem = Describe.problem(error)
            return nil
        }
    }

    /// Writes the Reading List as a bookmarks file you picked in a save dialog.
    func saveBookmarks(to url: URL) -> String? {
        do {
            try Exporter.saveBookmarks(list, to: url, protected: source.protectedFolders)
            return nil
        } catch let error as ExportError {
            return Describe.problem(error)
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Copying

    /// Puts a page's address on the clipboard, or several pages' as a Markdown list.
    @discardableResult
    func copy(_ items: [Item], to pasteboard: NSPasteboard = .general) -> Bool {
        guard !items.isEmpty else { return false }
        pasteboard.clearContents()
        if items.count == 1 { return pasteboard.setString(items[0].url, forType: .string) }
        let renderer = Renderer()
        return pasteboard.setString(items.map { "- " + renderer.link($0) }.joined(separator: "\n"), forType: .string)
    }
}
