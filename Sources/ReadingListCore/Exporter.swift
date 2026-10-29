import CryptoKit
import Foundation

public struct ExportOptions: Equatable, Sendable {
    /// `Reading List.md`, every page as a task.
    public var markdown = true
    /// `Reading List.html`, a bookmarks file for read-later and bookmark apps.
    public var bookmarks = true
    /// `Reading List.csv`, in Instapaper's layout.
    public var csv = true
    public var json = false
    /// A note of its own for each page, in `Pages`.
    public var notes = false
    public var renderer = Renderer()

    public init(markdown: Bool = true, bookmarks: Bool = true, csv: Bool = true, json: Bool = false, notes: Bool = false, renderer: Renderer = Renderer()) {
        self.markdown = markdown
        self.bookmarks = bookmarks
        self.csv = csv
        self.json = json
        self.notes = notes
        self.renderer = renderer
    }

    public static func == (a: ExportOptions, b: ExportOptions) -> Bool {
        (a.markdown, a.bookmarks, a.csv, a.json, a.notes) == (b.markdown, b.bookmarks, b.csv, b.json, b.notes)
    }
}

/// What an export did.
public struct ExportReport: Equatable, Sendable {
    public struct Failure: Equatable, Sendable {
        public var file: String
        public var reason: String
    }

    /// Pages that weren't in the export yet.
    public var newItems = 0
    /// Pages already exported that you've read since.
    public var newlyRead = 0
    /// Files written or brought up to date, from the export folder.
    public var written: [String] = []
    /// Files you've edited, which are left as they are.
    public var kept: [String] = []
    public var failed: [Failure] = []
    /// Entries in the Reading List that weren't web pages, and were left out.
    public var skipped = 0
    /// Safari listed none or far fewer pages than last time, as it can while iCloud is still
    /// syncing, so nothing was marked as removed from Safari. If the list stays that short for a
    /// day, the next export takes it as it is.
    public var heldBack = false

    public init() {}
}

public enum ExportError: Error, Equatable {
    /// The chosen folder is inside Safari's folder, which is never written to.
    case insideLibrary
    /// The folder's export record can't be read, so exporting could lose the pages it holds.
    case unreadableRecord
    /// The export record was written by a newer version.
    case newerRecord
    /// Another export into the same folder is running, like the app and the command line tool at once.
    case busy
    case cannotWrite(String)
}

/// What's been exported to a folder, kept in the folder itself as `.reading-list-export.json`. It
/// holds every page exported so far, so a page you later remove from Safari stays in the export.
/// And it holds what each file was when it was written, so a file you've edited is never overwritten.
struct ExportRecord: Codable, Equatable {
    static let currentVersion = 1

    struct File: Codable, Equatable {
        /// From the export folder, with its extension.
        var path: String
        /// The SHA-256 of the file as last written, to tell whether you've edited it since.
        var hash: String
        /// The SHA-256 of what it would have said when it was last left alone because you'd edited
        /// it, so that's said once for each change rather than on every run.
        var held: String?
    }

    var version = currentVersion
    var items: [String: Item] = [:]
    /// When Safari first listed far fewer pages than the export has, if it still does. After a day
    /// of that, the shorter list is taken as real.
    var shortSince: Date?
    /// By what the file is: `markdown`, `bookmarks`, `csv`, `json`, or `note:` and the page's ID.
    var files: [String: File] = [:]
}

/// Exports the Reading List into a folder: a Markdown note, a bookmarks file, a CSV in Instapaper's
/// layout, JSON, and if you like a note for each page. Each run adds what's new. A file you've
/// edited is never overwritten, and nothing is ever deleted.
public struct Exporter: Sendable {
    public static let recordName = ".reading-list-export.json"
    static let lockName = ".reading-list-export.lock"
    static let baseName = "Reading List"
    static let notesFolder = "Pages"
    /// Far bigger than any real record or note; anything bigger isn't one of ours.
    static let readLimit = 256 * 1024 * 1024
    /// How long a much shorter Reading List is waited on before it's believed.
    static let shortListGrace: TimeInterval = 86400

    public let destination: URL
    public var options: ExportOptions

    public init(destination: URL, options: ExportOptions = ExportOptions()) {
        self.destination = destination.standardizedFileURL
        self.options = options
    }

    /// Exports what's new or changed since the last run. Nothing is written inside any of the
    /// `protected` folders, like Safari's.
    public func export(_ list: ReadingList, protected: [URL] = [], now: Date = Date()) throws -> ExportReport {
        if protected.contains(where: { Self.isInside(destination, $0) }) { throw ExportError.insideLibrary }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let report = try FileLock.run(at: destination.appendingPathComponent(Self.lockName)) {
                try run(list, protected: protected, now: now)
            }
            guard let report else { throw ExportError.busy }
            return report
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.cannotWrite(error.localizedDescription)
        }
    }

    /// How many pages aren't in the export yet. Throws if the folder's record can't be read.
    public func newItems(_ list: ReadingList) throws -> Int {
        let record = try loadRecord()
        return Self.matched(list, to: record).items.filter { record.items[$0.id] == nil }.count
    }

    private func run(_ list: ReadingList, protected: [URL], now: Date) throws -> ExportReport {
        var record = try loadRecord()
        var report = ExportReport()
        report.skipped = list.skipped
        // A short list gets a day to fill back in. If it's still short after that, you really did
        // clear those pages, and they're marked as removed.
        var incomplete = Self.looksIncomplete(list, comparedTo: record)
        if incomplete {
            let since = record.shortSince ?? now
            record.shortSince = since
            if now.timeIntervalSince(since) >= Self.shortListGrace { incomplete = false }
        }
        if !incomplete { record.shortSince = nil }
        report.heldBack = incomplete
        Self.merge(Self.matched(list, to: record), into: &record, incomplete: incomplete, now: now, report: &report)
        let renderer = options.renderer
        let items = record.items.values.sorted(by: ReadingList.newest)
        var files = Writer(destination: destination, protected: protected, record: record, taken: Set(record.files.values.map { $0.path.lowercased() }))

        if options.markdown {
            files.write(key: "markdown", path: Self.baseName + ".md", content: renderer.overview(items), recreate: true, report: &report)
        }
        if options.bookmarks {
            files.write(key: "bookmarks", path: Self.baseName + ".html", content: renderer.bookmarks(items), recreate: true, report: &report)
        }
        if options.csv {
            files.write(key: "csv", path: Self.baseName + ".csv", content: renderer.instapaperCSV(items), recreate: true, report: &report)
        }
        if options.json {
            files.write(key: "json", path: Self.baseName + ".json", content: renderer.json(items), recreate: true, report: &report)
        }
        if options.notes {
            // Oldest first, so when two pages share a title the earlier one keeps the plain name.
            for item in items.reversed() {
                let path = Self.notesFolder + "/" + Renderer.safeName(item.title) + ".md"
                files.write(key: "note:\(item.id)", path: path, content: renderer.note(item), recreate: false, report: &report)
            }
        }
        try saveRecord(files.record)
        return report
    }

    // MARK: Merging

    /// Whether the list looks like Safari hasn't finished loading or syncing it: no pages at all
    /// when the export had some still in Safari, or fewer than half of them.
    static func looksIncomplete(_ list: ReadingList, comparedTo record: ExportRecord) -> Bool {
        let before = record.items.values.filter(\.inSafari).count
        if list.items.isEmpty { return before > 0 }
        return before >= 4 && list.items.count * 2 < before
    }

    /// The list with its IDs changed to the ones already in the record where it's clearly the same
    /// page under a new ID, as after iCloud rebuilt the Reading List or you moved to a new Mac: the
    /// same address, on a page the record has that the list no longer does under its old ID. Two
    /// pages that are both in the list are never merged.
    static func matched(_ list: ReadingList, to record: ExportRecord) -> ReadingList {
        let present = Set(list.items.map(\.id))
        var orphans: [String: [String]] = [:]
        for old in record.items.values.sorted(by: ReadingList.newest) where !present.contains(old.id) {
            orphans[old.url, default: []].append(old.id)
        }
        var list = list
        for index in list.items.indices where record.items[list.items[index].id] == nil {
            guard var ids = orphans[list.items[index].url], !ids.isEmpty else { continue }
            list.items[index].id = ids.removeFirst()
            orphans[list.items[index].url] = ids
        }
        return list
    }

    /// Adds the list to what's been exported before. Nothing exported is ever dropped: a page you
    /// remove from Safari stays, marked with when it was found gone, and keeps whether you'd read
    /// it. An `incomplete` list, one Safari is still syncing, adds what it has but marks nothing gone.
    static func merge(_ list: ReadingList, into record: inout ExportRecord, incomplete: Bool = false, now: Date, report: inout ExportReport) {
        if !incomplete {
            let present = Set(list.items.map(\.id))
            for (id, item) in record.items where item.inSafari && !present.contains(id) {
                record.items[id]?.removed = now
            }
        }
        for item in list.items {
            guard let old = record.items[item.id] else {
                record.items[item.id] = item
                report.newItems += 1
                continue
            }
            if item.read && !old.read { report.newlyRead += 1 }
            var merged = item
            merged.added = item.added ?? old.added
            merged.preview = item.preview ?? old.preview
            merged.siteName = item.siteName ?? old.siteName
            if item.read { merged.viewed = item.viewed ?? old.viewed }
            record.items[item.id] = merged
        }
    }

    // MARK: Writing files

    /// Writes files into the export folder, never over one you've edited.
    struct Writer {
        let destination: URL
        let protected: [URL]
        var record: ExportRecord
        var taken: Set<String>

        /// Writes `content` as the file known by `key`. A new file goes at `path`, or the next free
        /// name beside it if something is already there. A file written before is rewritten only
        /// if what it says changed and it's exactly as it was written; one you've edited is left
        /// alone, and said so once for each change it would have made. With `recreate`, a file
        /// you've deleted is written again; page notes you delete stay deleted.
        mutating func write(key: String, path: String, content: String, recreate: Bool, report: inout ExportReport) {
            let data = Data(content.utf8)
            let made = Exporter.hash(data)
            do {
                if let entry = record.files[key] {
                    let url = destination.appendingPathComponent(entry.path)
                    try checkWritable(url.deletingLastPathComponent())
                    if FileManager.default.fileExists(atPath: url.path) {
                        guard entry.hash != made else { return }
                        // A file that can't be read, like one iCloud Drive has offloaded, isn't one
                        // you edited: it's a failure, and the next export tries again.
                        guard let existing = Exporter.readLimited(url) else {
                            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "It couldn't be read to check whether you'd edited it."])
                        }
                        guard Exporter.hash(existing) == entry.hash else {
                            if entry.held != made {
                                record.files[key]?.held = made
                                report.kept.append(entry.path)
                            }
                            return
                        }
                        try data.write(to: url, options: .atomic)
                    } else {
                        guard recreate else { return }
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: url, options: .withoutOverwriting)
                    }
                    record.files[key] = .init(path: entry.path, hash: made)
                    report.written.append(entry.path)
                } else if !taken.contains(path.lowercased()), let existing = Exporter.readLimited(destination.appendingPathComponent(path)), existing == data {
                    // Exactly what would be written is already there, as after the record was
                    // moved away to start over: it's taken back rather than written again beside it.
                    try checkWritable(destination.appendingPathComponent(path).deletingLastPathComponent())
                    record.files[key] = .init(path: path, hash: made)
                    taken.insert(path.lowercased())
                } else {
                    let ext = (path as NSString).pathExtension
                    let free = Exporter.unique(String(path.dropLast(ext.count + 1)), ext: ext, in: destination, taken: &taken)
                    let url = destination.appendingPathComponent(free)
                    try checkWritable(url.deletingLastPathComponent())
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .withoutOverwriting)
                    record.files[key] = .init(path: free, hash: made)
                    report.written.append(free)
                }
            } catch {
                report.failed.append(.init(file: record.files[key]?.path ?? path, reason: error.localizedDescription))
            }
        }

        /// Makes sure `folder` is inside the export folder and outside every protected one, after
        /// following links, before anything is written there.
        private func checkWritable(_ folder: URL) throws {
            guard Exporter.isInside(folder, destination), !protected.contains(where: { Exporter.isInside(folder, $0) }) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "Its folder is outside the export folder or inside Safari's."])
            }
        }
    }

    /// `base` with `ext`, or with a number added if a file of yours or another export's file
    /// already has that name. Names are compared ignoring case, as the Mac does.
    static func unique(_ base: String, ext: String, in destination: URL, taken: inout Set<String>) -> String {
        var number = 1
        while true {
            let name = (number == 1 ? base : "\(base) (\(number))") + "." + ext
            if !taken.contains(name.lowercased()) && !FileManager.default.fileExists(atPath: destination.appendingPathComponent(name).path) {
                taken.insert(name.lowercased())
                return name
            }
            number += 1
        }
    }

    // MARK: Saving a bookmarks file on its own

    /// Writes the Reading List as a bookmarks file you chose in a save dialog, replacing it if you
    /// said to. Never inside a protected folder.
    public static func saveBookmarks(_ list: ReadingList, to url: URL, protected: [URL], renderer: Renderer = Renderer()) throws {
        guard !protected.contains(where: { isInside(url, $0) }) else { throw ExportError.insideLibrary }
        do {
            try Data(renderer.bookmarks(list.items).utf8).write(to: url, options: .atomic)
        } catch {
            throw ExportError.cannotWrite(error.localizedDescription)
        }
    }

    // MARK: Record

    var recordURL: URL { destination.appendingPathComponent(Self.recordName) }

    func loadRecord() throws -> ExportRecord {
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return ExportRecord() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = Self.readLimited(recordURL) else { throw ExportError.unreadableRecord }
        if let version = try? decoder.decode(Version.self, from: data).version, version > ExportRecord.currentVersion {
            throw ExportError.newerRecord
        }
        guard let record = try? decoder.decode(ExportRecord.self, from: data),
              record.files.values.allSatisfy({ Self.isSafePath($0.path) }),
              record.items.allSatisfy({ $0.key == $0.value.id && Links.web($0.value.url) == $0.value.url })
        else { throw ExportError.unreadableRecord }
        return record
    }

    private struct Version: Decodable {
        var version: Int
    }

    func saveRecord(_ record: ExportRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(record).write(to: recordURL, options: .atomic)
        } catch {
            throw ExportError.cannotWrite(error.localizedDescription)
        }
    }

    /// Whether a path from the record stays inside the export folder: a file name, or a folder
    /// and a file name, with nothing that climbs out or hides.
    static func isSafePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !path.contains("\0"), !path.contains("\\") else { return false }
        return parts.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") }
    }

    // MARK: Helpers

    static func readLimited(_ url: URL) -> Data? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= readLimit else { return nil }
        return try? Data(contentsOf: url)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `url` is `folder` or inside it, after following symbolic links.
    public static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let path = resolved(url).lowercased(), base = resolved(folder).lowercased()
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// The path with every link followed, including links above a folder that doesn't exist yet.
    static func resolved(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var path = existing.resolvingSymlinksInPath().path
        for component in rest { path = (path as NSString).appendingPathComponent(component) }
        return path
    }
}
