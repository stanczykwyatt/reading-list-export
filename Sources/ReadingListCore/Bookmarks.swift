import CryptoKit
import Foundation

public enum LibraryError: Error, Equatable {
    /// There's no Safari bookmarks file on this Mac yet.
    case notFound
    /// macOS blocked the read. Safari's bookmarks need Full Disk Access.
    case noPermission
    /// The file is there but laid out in a way this version doesn't know.
    case unrecognized(String)
}

/// Reads your Reading List from Safari's bookmarks file. The file is only ever read, never
/// written, and nothing else in Safari's folder is opened: not your history, not your open tabs,
/// not your bookmarks outside the Reading List.
public struct SafariBookmarks: Sendable {
    /// Where Safari keeps its bookmarks and Reading List, from the home folder.
    public static let relativePath = "Library/Safari/Bookmarks.plist"
    /// The folder Safari's bookmarks file is in, from the home folder.
    static let safariFolder = "Library/Safari"
    /// The title Safari gives the Reading List's folder inside the bookmarks file.
    static let readingListTitle = "com.apple.ReadingList"
    /// Far bigger than any real bookmarks file, even one holding years of saved pages.
    static let sizeLimit = 512 * 1024 * 1024
    /// More pages than anyone saves; a list longer than this is damage.
    static let itemLimit = 500_000
    static let titleLimit = 1000
    static let previewLimit = 4000

    public let file: URL

    public init(file: URL) {
        self.file = file.standardizedFileURL
    }

    public init(home: URL) {
        self.init(file: home.appendingPathComponent(Self.relativePath))
    }

    /// The real home folder, even inside the App Sandbox, where `NSHomeDirectory()` is the container.
    public static var realHome: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    // MARK: Reading

    /// Everything in your Reading List. Safari saves the file by writing a new one and swapping it
    /// in, so a single read always gets a whole file, never one half written.
    public func read() throws -> ReadingList {
        let data: Data
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            guard size <= Self.sizeLimit else { throw LibraryError.unrecognized("Safari's bookmarks file is unexpectedly large.") }
            data = try Data(contentsOf: file)
        } catch let error as LibraryError {
            throw error
        } catch {
            throw Self.libraryError(error)
        }
        return try Self.parse(data)
    }

    /// The folders nothing may ever be written into: Safari's own folder when it's the real
    /// bookmarks file, and just the file itself when it's a copy somewhere else.
    public var protectedFolders: [URL] {
        let folder = file.deletingLastPathComponent()
        return folder.lastPathComponent == "Safari" ? [folder] : [file]
    }

    /// What changes when Safari saves the file: its date, its size, and which file it is, since
    /// Safari swaps in a new one each time.
    public struct Stamp: Equatable, Sendable {
        var date: Date
        var size: Int
        var fileNumber: Int
    }

    /// When the file last changed, to tell cheaply whether there's anything new. Nil if macOS
    /// won't say, in which case it's read again each time.
    public func lastChange() -> Stamp? {
        // Asked of the file each time, since a URL keeps what it was told before.
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let date = attributes?[.modificationDate] as? Date else { return nil }
        return Stamp(date: date, size: attributes?[.size] as? Int ?? 0, fileNumber: attributes?[.systemFileNumber] as? Int ?? 0)
    }

    /// Turns a failed read into what it means for you.
    static func libraryError(_ error: Error) -> LibraryError {
        if let error = error as? CocoaError {
            if error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return .notFound }
            if error.code == .fileReadNoPermission { return .noPermission }
        }
        let code = ((error as NSError).underlyingErrors.first as NSError?)?.code ?? (error as NSError).code
        if code == Int(EPERM) || code == Int(EACCES) { return .noPermission }
        if code == Int(ENOENT) { return .notFound }
        return .unrecognized("Couldn't read Safari's bookmarks file: \(error.localizedDescription)")
    }

    // MARK: The file

    /// Reads the Reading List out of the bookmarks file's contents. Only the Reading List's folder
    /// is looked at; your other bookmarks are skipped over.
    static func parse(_ data: Data) throws -> ReadingList {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LibraryError.unrecognized("Safari's bookmarks file isn't in a form Reading List Export knows.")
        }
        guard let children = root["Children"] as? [Any] else {
            throw LibraryError.unrecognized("Safari's bookmarks file has no folders in it.")
        }
        // No Reading List folder yet is how Safari leaves a Mac where nothing was ever saved.
        guard let folder = children.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["Title"] as? String == readingListTitle }) else {
            return ReadingList()
        }
        guard let entries = (folder["Children"] ?? []) as? [Any] else {
            throw LibraryError.unrecognized("Safari's Reading List isn't laid out the way Reading List Export knows.")
        }
        guard entries.count <= itemLimit else { throw LibraryError.unrecognized("Safari's Reading List is unexpectedly long.") }
        var items: [Item] = []
        var seen = Set<String>()
        var skipped = 0
        for entry in entries {
            guard let entry = entry as? [String: Any] else { continue }
            // A folder or anything else that isn't a saved page isn't part of the list.
            guard entry["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf" else { continue }
            guard let url = Links.web(entry["URLString"] as? String) else {
                skipped += 1
                continue
            }
            let reading = entry["ReadingList"] as? [String: Any] ?? [:]
            let local = entry["ReadingListNonSync"] as? [String: Any] ?? [:]
            var id = cleanID(entry["WebBookmarkUUID"] as? String) ?? "url-" + digest(url)
            // Entries that share an ID all stay, each after the first under an ID of its own.
            var copy = 1
            while seen.contains(id) {
                id = "url-" + digest((cleanID(entry["WebBookmarkUUID"] as? String) ?? "") + "\u{1F}" + url + "\u{1F}\(copy)")
                copy += 1
            }
            seen.insert(id)
            let title = text((entry["URIDictionary"] as? [String: Any])?["title"], limit: titleLimit)
                ?? text(local["Title"], limit: titleLimit)
            items.append(Item(
                id: id,
                url: url,
                title: title ?? fallbackTitle(url),
                siteName: text(local["siteName"], limit: 200),
                preview: text(reading["PreviewText"], limit: previewLimit),
                added: date(reading["DateAdded"]),
                // Safari sets this when you open a page or mark it read, and removes it when you
                // mark it unread.
                read: reading["DateLastViewed"] != nil,
                viewed: date(reading["DateLastViewed"])
            ))
        }
        return ReadingList(items: items, skipped: skipped)
    }

    // MARK: Values

    /// A date from the file, or nil if it's missing or nowhere near a real one.
    static func date(_ value: Any?) -> Date? {
        guard let date = value as? Date else { return nil }
        let seconds = date.timeIntervalSince1970
        // Between 1995, before Safari or the web as most know it, and the year 2100.
        guard seconds.isFinite, seconds > 788_918_400, seconds < 4_102_444_800 else { return nil }
        return date
    }

    /// Text from the file on one line, with runs of spaces closed up, or nil if there's none.
    static func text(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String else { return nil }
        let joined = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        guard joined.count > limit else { return joined }
        return String(joined.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A title for a page Safari never fetched one for: its address without the scheme.
    static func fallbackTitle(_ url: String) -> String {
        var rest = Substring(url)
        if let range = rest.range(of: "://") { rest = rest[range.upperBound...] }
        if rest.hasPrefix("www.") { rest = rest.dropFirst(4) }
        while rest.hasSuffix("/") { rest = rest.dropLast() }
        return String(rest.prefix(200))
    }

    /// An ID from the file, kept only if it's letters, digits and dashes, so it's safe in file
    /// names, front matter and the export record.
    static func cleanID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 128,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return value
    }

    /// A short, stable fingerprint of some text, for IDs made from addresses.
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
