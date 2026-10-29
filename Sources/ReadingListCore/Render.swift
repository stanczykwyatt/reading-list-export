import Foundation

/// Turns Reading List items into the files that are written: a Markdown note, a bookmarks file
/// for read-later and bookmark apps, a CSV in Instapaper's layout, and JSON.
public struct Renderer: Sendable {
    public var timeZone: TimeZone
    public var locale: Locale

    /// How much of a page's preview the Markdown shows. All of it is in the JSON.
    static let previewLength = 280

    public init(timeZone: TimeZone = .current, locale: Locale = .current) {
        self.timeZone = timeZone
        self.locale = locale
    }

    // MARK: Markdown

    /// The Reading List as one note: unread pages first, as open tasks, then read ones, checked
    /// off. Pages you've since removed from Safari stay, marked as removed.
    public func overview(_ items: [Item]) -> String {
        let unread = items.filter { !$0.read }.sorted(by: ReadingList.newest)
        let read = items.filter(\.read).sorted(by: ReadingList.newest)
        var lines = ["---"]
        lines.append("title: \"Reading List\"")
        lines.append("pages: \(items.count)")
        lines.append("unread: \(unread.count)")
        lines.append("source: Safari Reading List")
        lines.append("tags:")
        lines.append("  - reading-list")
        lines.append("---")
        lines.append("")
        lines.append("# Reading List")
        lines.append("")
        if items.isEmpty {
            lines.append("*Nothing yet. Add a page to your Reading List in Safari, and the next export adds it here.*")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        var counts = ["\(unread.count) unread", "\(read.count) read"]
        let gone = items.filter { !$0.inSafari }.count
        if gone > 0 { counts.append("\(gone) no longer in Safari") }
        lines.append(counts.joined(separator: " · "))
        lines.append("")
        for (heading, group) in [("Unread", unread), ("Read", read)] where !group.isEmpty {
            lines.append("## \(heading)")
            lines.append("")
            for item in group {
                lines.append(contentsOf: entry(item))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// One page as a task: the linked title, where it's from and when, and its preview below.
    func entry(_ item: Item) -> [String] {
        var parts = [link(item)]
        if !item.site.isEmpty, item.site != Self.inline(item.title) { parts.append(Self.inline(item.site)) }
        if let added = item.added { parts.append("added \(day(added))") }
        if item.read, let viewed = item.viewed { parts.append("read \(day(viewed))") }
        if let removed = item.removed { parts.append("removed from Safari \(day(removed))") }
        var lines = ["- [\(item.read ? "x" : " ")] " + parts.joined(separator: " · ")]
        if let preview = item.preview.map(Self.shortened).map(Self.inline).map(Self.startsAsText), !preview.isEmpty {
            lines.append("  > " + preview)
        }
        return lines
    }

    /// A page's own note, for those who keep one note per page.
    public func note(_ item: Item) -> String {
        var lines = ["---"]
        lines.append("title: \(Self.yaml(item.title))")
        lines.append("url: \(Self.yaml(item.url))")
        if !item.site.isEmpty { lines.append("site: \(Self.yaml(item.site))") }
        if let added = item.added { lines.append("added: \(day(added))") }
        lines.append("read: \(item.read)")
        if item.read, let viewed = item.viewed { lines.append("read-on: \(day(viewed))") }
        if let removed = item.removed { lines.append("removed-from-safari: \(day(removed))") }
        lines.append("source: Safari Reading List")
        lines.append("reading-list-id: \(Self.yaml(item.id))")
        lines.append("tags:")
        lines.append("  - reading-list")
        lines.append("---")
        lines.append("")
        lines.append("# \(Self.inline(item.title).nonEmpty ?? "Untitled page")")
        lines.append("")
        var about = ["[Open the page](<\(Self.markdownURL(item.url))>)"]
        if !item.site.isEmpty { about.append(Self.inline(item.site)) }
        if let added = item.added { about.append("added \(longDay(added))") }
        about.append(item.read ? (item.viewed.map { "read \(longDay($0))" } ?? "read") : "unread")
        lines.append(about.joined(separator: " · "))
        lines.append("")
        if let preview = item.preview.map(Self.inline).map(Self.startsAsText), !preview.isEmpty {
            lines.append("> " + preview)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// The page's title, linked to it.
    public func link(_ item: Item) -> String {
        "[\(Self.inline(item.title).nonEmpty ?? "Untitled page")](<\(Self.markdownURL(item.url))>)"
    }

    /// An address inside `<…>` in a Markdown link, where angle brackets could end it early and a
    /// backslash could escape the closing one.
    static func markdownURL(_ url: String) -> String {
        url.replacingOccurrences(of: "\\", with: "%5C").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
    }

    /// Text that starts as plain text, not as a rule or a list, where Markdown would read a leading
    /// `---`, `- ` or `1. ` as one.
    static func startsAsText(_ text: String) -> String {
        guard let first = text.first else { return text }
        if "-+".contains(first) { return "\\" + text }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, let mark = text.dropFirst(digits.count).first, mark == "." || mark == ")" {
            return digits + "\\" + text.dropFirst(digits.count)
        }
        return text
    }

    /// A preview cut to a few lines' worth, at a word break.
    static func shortened(_ text: String) -> String {
        guard text.count > previewLength else { return text }
        var cut = String(text.prefix(previewLength))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > previewLength / 2 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }

    // MARK: Bookmarks file

    /// The Reading List as a bookmarks file, the layout every browser exports, in one folder named
    /// Reading List. Linkding, Karakeep, Raindrop.io, Firefox, Chrome and most bookmark and
    /// read-later apps import it. Unread pages are marked `TOREAD="1"`, which Linkding keeps as
    /// unread, and each page's preview is its description. Pages you've cleared from Safari are
    /// tagged `removed-from-safari` and never marked to read, so they don't come back as a backlog.
    public func bookmarks(_ items: [Item]) -> String {
        var lines = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- Safari Reading List, exported by Reading List Export. -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
            "    <DT><H3>Reading List</H3>",
            "    <DL><p>",
        ]
        for item in items.sorted(by: ReadingList.newest) {
            var anchor = "        <DT><A HREF=\"\(Self.html(item.url))\""
            if let added = item.added { anchor += " ADD_DATE=\"\(Int(added.timeIntervalSince1970))\"" }
            anchor += item.inSafari ? " TAGS=\"reading-list\"" : " TAGS=\"reading-list,removed-from-safari\""
            if !item.read && item.inSafari { anchor += " TOREAD=\"1\"" }
            lines.append(anchor + ">\(Self.html(item.title))</A>")
            if let preview = item.preview.map(Self.html), !preview.isEmpty {
                lines.append("        <DD>\(preview)")
            }
        }
        lines.append("    </DL><p>")
        lines.append("</DL><p>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Text for HTML, in an attribute or between tags: the special characters escaped, and
    /// anything invisible or on another line taken out, so nothing can end the tag early.
    static func html(_ value: String) -> String {
        var out = ""
        for scalar in visible(value).unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\n", "\r", "\t": out += " "
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: CSV and JSON

    /// The Reading List in Instapaper's CSV layout: URL, Title, Selection, Folder and Timestamp.
    /// Wallabag, Readwise Reader and other read-later apps import it. Unread pages go in the
    /// Unread folder and read ones in Archive, as Instapaper does, and the preview is the selection.
    /// Pages you've cleared from Safari go in Archive too, so they don't come back as unread.
    public func instapaperCSV(_ items: [Item]) -> String {
        var rows = ["URL,Title,Selection,Folder,Timestamp"]
        for item in items.sorted(by: ReadingList.newest) {
            let fields = [
                item.url, item.title, item.preview ?? "", item.read || !item.inSafari ? "Archive" : "Unread",
                item.added.map { String(Int($0.timeIntervalSince1970)) } ?? "",
            ]
            rows.append(fields.map(Self.csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// One CSV field, quoted. Text a spreadsheet would run as a formula gets a leading apostrophe,
    /// so a page's title can't become one. A title that only starts with a minus before a number
    /// or a space, like "-30% off", is left as written, since read-later apps import it as is.
    static func csvField(_ value: String) -> String {
        var text = visible(value).replacingOccurrences(of: "\n", with: " ")
        let scalars = Array(text.unicodeScalars.prefix(2))
        if let first = scalars.first, "=+-@".unicodeScalars.contains(first), Double(text) == nil {
            let plainMinus = first == "-" && scalars.count > 1 && (scalars[1].properties.numericType != nil || scalars[1] == " ")
            if !plainMinus { text = "'" + text }
        }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Every page with everything known about it, as JSON for scripts and other apps.
    public func json(_ items: [Item]) -> String {
        let file = ReadingListFile(items: items.sorted(by: ReadingList.newest).map { item in
            .init(
                id: item.id, title: item.title, url: item.url, site: item.site.nonEmpty, preview: item.preview,
                added: item.added.map(isoDate), read: item.read, lastViewed: item.viewed.map(isoDate),
                inSafari: item.inSafari, removed: item.removed.map(isoDate)
            )
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(file)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: Dates

    func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// A day, like 2026-04-30, which sorts in order.
    public func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A day in words, like April 30, 2026.
    func longDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: Text

    /// A double-quoted YAML string, safe for any title.
    static func yaml(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default:
                // Control and invisible formatting characters are written as escapes, so nothing
                // hides in the front matter. YAML reads them back as they were.
                if [.control, .format, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory) {
                    out += scalar.value > 0xFFFF ? String(format: "\\U%08X", scalar.value) : String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Text on one line, escaped for Markdown.
    static func inline(_ text: String) -> String {
        escape(visible(text).components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces))
    }

    /// Escapes what Markdown would otherwise read as formatting or HTML, so titles come out as
    /// written. Only characters that can start formatting are escaped, to keep the text readable.
    static func escape(_ text: String) -> String {
        let characters = Array(visible(text))
        var out = ""
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let previous = index > 0 ? characters[index - 1] : nil
            // Single characters that start formatting, and the pairs Obsidian reads as comments,
            // highlights and strikethrough. An ampersand only when it could start an entity.
            let pair = "%=~".contains(character) && (next == character || previous == character)
            let entity = character == "&" && Self.startsEntity(characters[(index + 1)...])
            if "\\`*_<>[]#$|".contains(character) || pair || entity { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// Whether what follows an ampersand would make it an HTML entity, like `&amp;` or `&#38;`.
    static func startsEntity(_ rest: ArraySlice<Character>) -> Bool {
        let name = rest.prefix(12).prefix { $0.isLetter || $0.isNumber || $0 == "#" }
        return !name.isEmpty && rest.dropFirst(name.count).first == ";"
    }

    /// Text without control characters or the invisible marks that flip its direction, which
    /// could make words read differently from what's there.
    static func visible(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isHidden(scalar) || scalar == "\n" {
            out.append(scalar)
        }
        return String(out)
    }

    static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
            || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
            || scalar.value == 0x200E || scalar.value == 0x200F || scalar.value == 0x061C
            // Zero-width spaces and the word joiner, which can hide inside a word. Joiners used in
            // emoji are kept.
            || scalar.value == 0x200B || scalar.value == 0x2060 || scalar.value == 0xFEFF
    }

    // MARK: File names

    /// A name that's safe as a file name on any Mac, and inside an Obsidian `[[link]]`.
    public static func safeName(_ name: String, fallback: String = "Untitled page") -> String {
        var out = ""
        for scalar in name.unicodeScalars {
            if "/\\:*?\"<>|[]#^".unicodeScalars.contains(scalar) || isHidden(scalar) {
                out += " "
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        var cleaned = out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        // File names are limited to 255 bytes, and a number and an extension come too.
        while cleaned.utf8.count > 120 { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? fallback : cleaned
    }
}

/// The layout of `Reading List.json`.
struct ReadingListFile: Codable {
    struct Entry: Codable {
        var id: String
        var title: String
        var url: String
        var site: String?
        var preview: String?
        var added: String?
        var read: Bool
        var lastViewed: String?
        var inSafari: Bool
        var removed: String?

        enum CodingKeys: String, CodingKey {
            case id, title, url, site, preview, added, read, removed
            case lastViewed = "last_viewed", inSafari = "in_safari"
        }
    }

    var format = "reading-list-export 1"
    var items: [Entry]
}
