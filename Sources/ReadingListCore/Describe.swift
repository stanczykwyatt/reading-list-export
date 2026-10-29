import Foundation

/// The wording shown in the menu, the window and the command line.
public enum Describe {
    public static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : plural ?? singular + "s")"
    }

    /// How long ago, in the menu's words: "just now", "5 min ago", "3 hr ago", "yesterday", "4 days ago".
    public static func relative(_ date: Date, now: Date) -> String {
        let seconds = min(now.timeIntervalSince(date), 1e11)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) hr ago" }
        let days = Int(seconds / 86400)
        if days < 60 { return days == 1 ? "yesterday" : "\(days) days ago" }
        let months = days / 30
        if months < 24 { return "\(months) months ago" }
        return "\(days / 365) years ago"
    }

    /// A path with the home folder written as `~`.
    public static func path(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path, base = home.standardizedFileURL.path
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~" + path.dropFirst(base.count) }
        return path
    }

    /// The Reading List in a few words, like "12 unread · 30 read".
    public static func totals(_ list: ReadingList) -> String {
        list.items.isEmpty ? "Reading List is empty" : "\(list.unread.count) unread · \(list.read.count) read"
    }

    /// Entries that weren't web pages, like "2 entries that weren't web pages".
    public static func skipped(_ count: Int) -> String {
        count == 1 ? "1 entry that wasn't a web page" : "\(count) entries that weren't web pages"
    }

    /// What an export did, in one line.
    public static func summary(_ report: ExportReport) -> String {
        var parts: [String] = []
        if report.newItems > 0 { parts.append("added \(count(report.newItems, "new page"))") }
        if report.newlyRead > 0 { parts.append("\(report.newlyRead) newly read") }
        if !report.written.isEmpty && parts.isEmpty { parts.append("updated \(count(report.written.count, "file"))") }
        if !report.kept.isEmpty { parts.append("kept \(count(report.kept.count, "edited file"))") }
        if !report.failed.isEmpty { parts.append("\(report.failed.count) failed") }
        if parts.isEmpty { return "Nothing new" }
        return capitalized(parts.joined(separator: ", "))
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    public static func problem(_ error: LibraryError) -> String {
        switch error {
        case .notFound: "No Safari bookmarks on this Mac yet. Open Safari once and add a page to your Reading List."
        case .noPermission: "Reading List Export needs Full Disk Access to read Safari's Reading List."
        case .unrecognized(let detail): detail
        }
    }

    public static func problem(_ error: ExportError) -> String {
        switch error {
        case .insideLibrary: "Choose a folder outside Safari's folder. Nothing is ever written there."
        case .unreadableRecord: "The folder's \(Exporter.recordName) can't be read, so exporting could lose pages it holds. To start over, move it and the files exported with it out of the folder."
        case .newerRecord: "This folder was exported by a newer version of Reading List Export. Update to keep exporting to it."
        case .busy: "Another export into this folder is running. Try again once it's done."
        case .cannotWrite(let detail): "Couldn't write to the export folder: \(detail)"
        }
    }
}
