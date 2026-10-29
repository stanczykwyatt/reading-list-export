import Foundation
import Testing
@testable import ReadingListCore

@Suite("Writing the files")
struct RenderTests {
    let renderer = Fixtures.renderer

    // MARK: Markdown

    @Test func theNoteListsUnreadThenRead() {
        let note = renderer.overview(Fixtures.list.items)
        #expect(note.hasPrefix("---\ntitle: \"Reading List\"\npages: 3\nunread: 2\nsource: Safari Reading List\ntags:\n  - reading-list\n---\n"))
        #expect(note.contains("2 unread · 1 read"))
        let unread = note.range(of: "## Unread")!.lowerBound, read = note.range(of: "## Read")!.lowerBound
        #expect(unread < read)
        #expect(note.contains("- [ ] [How tide pools survive winter](<https://tidewatch.example.com/a1>) · tidewatch.example.com · added 2026-04-29"))
        #expect(note.contains("- [x] [A field guide to lichens](<https://lichens.example.org/guide>) · Lichen Society · added 2026-04-26 · read 2026-04-28"))
        #expect(note.contains("  > Every January the pools freeze at the edges, and yet the anemones are back by March."))
        // The newer unread page comes first.
        #expect(note.range(of: "tide pools")!.lowerBound < note.range(of: "trains run late")!.lowerBound)
    }

    @Test func anEmptyListSaysSo() {
        let note = renderer.overview([])
        #expect(note.contains("pages: 0") && note.contains("*Nothing yet."))
        #expect(!note.contains("## Unread"))
    }

    @Test func removedPagesAreMarked() {
        let gone = Fixtures.item("G1", removed: Fixtures.date)
        let note = renderer.overview([gone])
        #expect(note.contains("removed from Safari 2026-04-30"))
        #expect(note.contains("1 no longer in Safari"))
    }

    @Test func titlesCantBreakTheMarkdown() {
        let item = Fixtures.item(title: "[Click](javascript:x) | <b>bold</b> **now** #tag", url: "https://a.example.com/p?a=<x>", preview: "line one\nline two ==hi==")
        let entry = renderer.entry(item).joined(separator: "\n")
        #expect(entry.contains("\\[Click\\](javascript:x) \\| \\<b\\>bold\\</b\\> \\*\\*now\\*\\* \\#tag"))
        #expect(entry.contains("(<https://a.example.com/p?a=%3Cx%3E>)"))
        #expect(entry.contains("  > line one line two \\=\\=hi\\=\\="))
        #expect(entry.split(separator: "\n").count == 2)
    }

    @Test func addressesAndPreviewsCantBreakTheMarkdown() {
        #expect(Renderer.markdownURL("https://a.example.com/x\\") == "https://a.example.com/x%5C")
        #expect(Renderer.startsAsText("--- not a rule") == "\\--- not a rule")
        #expect(Renderer.startsAsText("1. Not a list") == "1\\. Not a list")
        #expect(Renderer.startsAsText("1999 was a year") == "1999 was a year")
        let item = Fixtures.item(preview: "- looks like a list")
        #expect(renderer.entry(item)[1] == "  > \\- looks like a list")
    }

    @Test func removedPagesDontComeBackAsUnread() {
        let gone = Fixtures.item("G1", removed: Fixtures.date)
        let html = renderer.bookmarks([gone])
        #expect(html.contains("TAGS=\"reading-list,removed-from-safari\"") && !html.contains("TOREAD"))
        #expect(renderer.instapaperCSV([gone]).contains("\"Archive\""))
    }

    @Test func aSiteSameAsTheTitleIsntRepeated() {
        let item = Fixtures.item(title: "Lichen Society", site: "Lichen Society")
        #expect(!renderer.entry(item)[0].contains("· Lichen Society ·"))
    }

    @Test func longPreviewsAreShortenedAtAWord() {
        let text = String(repeating: "pebbles and ", count: 60)
        let short = Renderer.shortened(text)
        #expect(short.count <= Renderer.previewLength + 1 && short.hasSuffix("…"))
        #expect(!short.dropLast().hasSuffix(" "))
        #expect(Renderer.shortened("short") == "short")
    }

    @Test func aPagesNote() {
        let item = Fixtures.item("N1", title: "Quote \"marks\" and\ttabs", site: "Tide Watch", read: true, viewedDaysAgo: 1)
        let note = renderer.note(item)
        #expect(note.contains("title: \"Quote \\\"marks\\\" and\\ttabs\""))
        #expect(note.contains("url: \"https://tidewatch.example.com/n1\""))
        #expect(note.contains("read: true\nread-on: 2026-04-29"))
        #expect(note.contains("reading-list-id: \"N1\""))
        #expect(note.contains("[Open the page](<https://tidewatch.example.com/n1>) · Tide Watch · added April 27, 2026 · read April 29, 2026"))
        #expect(note.contains("> Every January"))
    }

    @Test func yamlEscapesWhatCouldHide() {
        #expect(Renderer.yaml("a\u{202E}b\u{0007}") == "\"a\\u202Eb\\u0007\"")
        #expect(Renderer.yaml("back\\slash") == "\"back\\\\slash\"")
    }

    // MARK: Bookmarks file

    @Test func theBookmarksFile() {
        let html = renderer.bookmarks(Fixtures.list.items)
        #expect(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"))
        #expect(html.contains("<DT><H3>Reading List</H3>"))
        let added = Int(Fixtures.date.timeIntervalSince1970) - 86400
        #expect(html.contains("<DT><A HREF=\"https://tidewatch.example.com/a1\" ADD_DATE=\"\(added)\" TAGS=\"reading-list\" TOREAD=\"1\">How tide pools survive winter</A>"))
        #expect(html.contains("<A HREF=\"https://lichens.example.org/guide\" ADD_DATE=\"\(Int(Fixtures.date.timeIntervalSince1970) - 4 * 86400)\" TAGS=\"reading-list\">A field guide to lichens</A>"))
        #expect(html.contains("<DD>Every January the pools freeze"))
        #expect(html.components(separatedBy: "TOREAD").count - 1 == 2)
        #expect(html.hasSuffix("    </DL><p>\n</DL><p>\n"))
    }

    @Test func nothingEscapesATagInTheBookmarksFile() {
        let item = Fixtures.item(title: "</A><script>x</script>", url: "https://a.example.com/?q=\"&b='", preview: "a\nb <i>")
        let html = renderer.bookmarks([item])
        #expect(!html.contains("<script>") && !html.contains("<i>"))
        #expect(html.contains("HREF=\"https://a.example.com/?q=&quot;&amp;b='\""))
        #expect(html.contains("&lt;/A&gt;&lt;script&gt;x&lt;/script&gt;</A>"))
        #expect(html.contains("<DD>a b &lt;i&gt;"))
    }

    @Test func anUndatedPageHasNoAddDate() {
        #expect(!renderer.bookmarks([Fixtures.item(daysAgo: nil)]).contains("ADD_DATE"))
    }

    // MARK: CSV and JSON

    @Test func theInstapaperCSV() {
        let csv = renderer.instapaperCSV(Fixtures.list.items)
        let rows = csv.components(separatedBy: "\r\n")
        #expect(rows[0] == "URL,Title,Selection,Folder,Timestamp")
        #expect(rows[1] == "\"https://tidewatch.example.com/a1\",\"How tide pools survive winter\",\"Every January the pools freeze at the edges, and yet the anemones are back by March.\",\"Unread\",\"\(Int(Fixtures.date.timeIntervalSince1970) - 86400)\"")
        #expect(rows[2].contains("\"Archive\""))
        #expect(rows[3].contains("\"\",\"Unread\""))
        #expect(csv.hasSuffix("\r\n") && rows.count == 5)
    }

    @Test func csvFieldsAreQuotedAndSafe() {
        #expect(Renderer.csvField("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(Renderer.csvField("-12") == "\"-12\"")
        #expect(Renderer.csvField("@home\nnext") == "\"'@home next\"")
    }

    @Test func aTitleStartingWithAMinusAndANumberIsKept() {
        #expect(Renderer.csvField("-30% off this week") == "\"-30% off this week\"")
        #expect(Renderer.csvField("- a dash and a space") == "\"- a dash and a space\"")
        #expect(Renderer.csvField("-cmd|' /C calc'!A0") == "\"'-cmd|' /C calc'!A0\"")
        #expect(Renderer.csvField("+1 for this") == "\"'+1 for this\"")
    }

    @Test func theJSON() throws {
        let gone = Fixtures.item("G1", removed: Fixtures.date)
        let json = renderer.json(Fixtures.list.items + [gone])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["format"] as? String == "reading-list-export 1")
        let items = try #require(object["items"] as? [[String: Any]])
        #expect(items.count == 4)
        let lichens = try #require(items.first { $0["id"] as? String == "A2" })
        #expect(lichens["read"] as? Bool == true && lichens["last_viewed"] as? String == "2026-04-28T09:41:00-05:00")
        #expect(lichens["site"] as? String == "Lichen Society" && lichens["in_safari"] as? Bool == true)
        let removed = try #require(items.first { $0["id"] as? String == "G1" })
        #expect(removed["in_safari"] as? Bool == false && removed["removed"] as? String == "2026-04-30T09:41:00-05:00")
    }

    // MARK: Names and dates

    @Test(arguments: [
        ("A/B: C?", "A B C"), ("...hidden", "hidden"), ("[[Link]] #tag", "Link tag"), ("", "Untitled page"), ("   ", "Untitled page"),
    ])
    func safeFileNames(_ name: String, _ expected: String) {
        #expect(Renderer.safeName(name) == expected)
    }

    @Test func longNamesFitInAFileName() {
        #expect(Renderer.safeName(String(repeating: "é", count: 300)).utf8.count <= 120)
    }

    @Test func daysAreInYourTimeZone() {
        let late = Date(timeIntervalSince1970: 1_777_600_000) // 2026-05-01 01:46 UTC
        #expect(renderer.day(late) == "2026-04-30")
        #expect(Renderer(timeZone: TimeZone(identifier: "UTC")!).day(late) == "2026-05-01")
    }

    @Test func invisibleCharactersAreRemoved() {
        #expect(Renderer.visible("a\u{202E}b\u{200F}c\u{0000}d\ne") == "abcd\ne")
        #expect(Renderer.inline("x\u{2066}y") == "xy")
    }
}
