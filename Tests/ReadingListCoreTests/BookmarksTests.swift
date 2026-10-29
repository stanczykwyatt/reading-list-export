import Foundation
import Testing
@testable import ReadingListCore

@Suite("Reading Safari's bookmarks file")
struct BookmarksTests {
    let folder = Fixtures.Folder()
    var home: URL { folder.url }

    private func read(_ entries: [Fixtures.Entry]) throws -> ReadingList {
        try Fixtures.write(entries, to: home)
        return try SafariBookmarks(home: home).read()
    }

    @Test func readsEveryPage() throws {
        let added = Fixtures.date.addingTimeInterval(-5 * 86400), viewed = Fixtures.date.addingTimeInterval(-86400)
        let list = try read([
            Fixtures.Entry(uuid: "UUID-READ", url: "https://lichens.example.org/guide", title: "A field guide to lichens", added: added, viewed: viewed,
                           preview: "Crusty, leafy and shrubby.", siteName: "Lichen Society"),
            Fixtures.Entry(uuid: "UUID-UNREAD", url: "https://rails.example.net/snow", title: "Why trains run late in the snow", added: Fixtures.date, preview: nil),
        ])
        #expect(list.items.count == 2 && list.skipped == 0)
        let unread = try #require(list.item("UUID-UNREAD"))
        #expect(unread.title == "Why trains run late in the snow" && unread.url == "https://rails.example.net/snow")
        #expect(!unread.read && unread.viewed == nil && unread.preview == nil && unread.added == Fixtures.date)
        #expect(unread.site == "rails.example.net")
        let read = try #require(list.item("UUID-READ"))
        #expect(read.read && read.viewed == viewed && read.added == added)
        #expect(read.preview == "Crusty, leafy and shrubby." && read.site == "Lichen Society")
        // Newest first.
        #expect(list.items.map(\.id) == ["UUID-UNREAD", "UUID-READ"])
        #expect(list.unread.map(\.id) == ["UUID-UNREAD"] && list.read.map(\.id) == ["UUID-READ"])
    }

    @Test func neverReadsOtherBookmarks() throws {
        let list = try read([Fixtures.Entry()])
        #expect(list.items.count == 1)
        #expect(!list.items.contains { $0.url.contains("favorite.example.com") })
    }

    @Test func aMacWithNoReadingListYetIsEmpty() throws {
        try Fixtures.write([], to: home, readingList: false)
        #expect(try SafariBookmarks(home: home).read() == ReadingList())
        try Fixtures.write([], to: home)
        #expect(try SafariBookmarks(home: home).read().items.isEmpty)
    }

    @Test func readsTheTextFormToo() throws {
        try Fixtures.write([Fixtures.Entry(uuid: "X1")], to: home, format: .xml)
        #expect(try SafariBookmarks(home: home).read().items.map(\.id) == ["X1"])
    }

    @Test func leavesOutWhatIsntAWebPage() throws {
        let list = try read([
            Fixtures.Entry(url: "javascript:alert(1)"),
            Fixtures.Entry(url: "file:///Users/someone/notes.txt"),
            Fixtures.Entry(url: "data:text/html,<b>hi</b>"),
            Fixtures.Entry(url: nil),
            Fixtures.Entry(url: "https://"),
            Fixtures.Entry(url: "https://ok.example.com/fine"),
        ])
        #expect(list.items.map(\.url) == ["https://ok.example.com/fine"])
        #expect(list.skipped == 5)
    }

    @Test func skipsFoldersAndOddEntries() throws {
        var plist = Fixtures.bookmarksFile([Fixtures.Entry(uuid: "KEEP"), Fixtures.Entry(uuid: "FOLDER", type: "WebBookmarkTypeList")])
        var children = plist["Children"] as! [Any]
        var reading = children[3] as! [String: Any]
        reading["Children"] = (reading["Children"] as! [Any]) + ["not a dictionary", 42]
        children[3] = reading
        plist["Children"] = children
        try Fixtures.write(plist: plist, to: home)
        let list = try SafariBookmarks(home: home).read()
        #expect(list.items.map(\.id) == ["KEEP"] && list.skipped == 0)
    }

    @Test func aPageWithNoTitleUsesItsAddress() throws {
        let list = try read([Fixtures.Entry(url: "https://www.quiet.example.com/essays/", title: nil), Fixtures.Entry(url: "https://b.example.com/", title: "   ")])
        #expect(Set(list.items.map(\.title)) == ["quiet.example.com/essays", "b.example.com"])
    }

    @Test func aPageWithNoIDGetsOneFromItsAddress() throws {
        let first = try read([Fixtures.Entry(uuid: nil, url: "https://a.example.com/x")])
        let again = try read([Fixtures.Entry(uuid: nil, url: "https://a.example.com/x")])
        let id = try #require(first.items.first?.id)
        #expect(id.hasPrefix("url-") && id == again.items.first?.id)
    }

    @Test func unsafeIDsAreReplaced() throws {
        let list = try read([Fixtures.Entry(uuid: "../../escape", url: "https://a.example.com/x"), Fixtures.Entry(uuid: "ok-ID-1", url: "https://b.example.com/")])
        #expect(Set(list.items.map(\.id)).contains("ok-ID-1"))
        #expect(list.items.allSatisfy { SafariBookmarks.cleanID($0.id) == $0.id })
    }

    @Test func twoPagesWithOneIDAreBothKept() throws {
        let list = try read([Fixtures.Entry(uuid: "SAME", url: "https://a.example.com/"), Fixtures.Entry(uuid: "SAME", url: "https://b.example.com/")])
        #expect(list.items.count == 2)
        #expect(Set(list.items.map(\.id)).count == 2)
        #expect(list.items.contains { $0.id == "SAME" })
    }

    @Test func threePagesWithOneIDAreAllKept() throws {
        let list = try read([
            Fixtures.Entry(uuid: "SAME", url: "https://a.example.com/"), Fixtures.Entry(uuid: "SAME", url: "https://a.example.com/"),
            Fixtures.Entry(uuid: "SAME", url: "https://a.example.com/"),
        ])
        #expect(list.items.count == 3 && Set(list.items.map(\.id)).count == 3)
    }

    @Test func zeroWidthCharactersAreKeptOutOfAddressesAndTitles() throws {
        let list = try read([Fixtures.Entry(url: "https://exa\u{200B}mple.com/"), Fixtures.Entry(uuid: "OK", url: "https://ok.example.com/", title: "Zero\u{200B}width\u{FEFF}")])
        #expect(list.items.map(\.id) == ["OK"] && list.skipped == 1)
        #expect(Renderer.inline(list.items[0].title) == "Zerowidth")
        #expect(Renderer.visible("👩\u{200D}🔬") == "👩\u{200D}🔬")
    }

    @Test func impossibleDatesAreDropped() throws {
        let list = try read([
            Fixtures.Entry(uuid: "OLD", added: Date(timeIntervalSince1970: 0)),
            Fixtures.Entry(uuid: "FAR", added: Date(timeIntervalSince1970: 9e9), viewed: Date(timeIntervalSince1970: 1)),
        ])
        #expect(list.items.allSatisfy { $0.added == nil })
        // Still read, even with a date that can't be right.
        let far = try #require(list.item("FAR"))
        #expect(far.read && far.viewed == nil)
    }

    @Test func textIsTidiedAndCut() throws {
        let long = String(repeating: "word ", count: 2000)
        let list = try read([Fixtures.Entry(title: "  Two\n\tlines  here ", preview: long)])
        let item = try #require(list.items.first)
        #expect(item.title == "Two lines here")
        #expect(item.preview!.count <= SafariBookmarks.previewLimit && item.preview!.hasSuffix("…"))
    }

    @Test func aMissingFileIsNotFound() {
        #expect(throws: LibraryError.notFound) { try SafariBookmarks(home: home).read() }
    }

    @Test func aLockedFileNeedsPermission() throws {
        let file = try Fixtures.write([Fixtures.Entry()], to: home)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        #expect(throws: LibraryError.noPermission) { try SafariBookmarks(file: file).read() }
    }

    @Test(arguments: [Data(), Data("not a plist".utf8), Data("<?xml version=\"1.0\"?><plist><array/></plist>".utf8)])
    func aDamagedFileIsUnrecognized(_ data: Data) throws {
        let safari = home.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        try data.write(to: safari.appendingPathComponent("Bookmarks.plist"))
        #expect {
            try SafariBookmarks(home: home).read()
        } throws: { error in
            if case LibraryError.unrecognized = error { return true }
            return false
        }
    }

    @Test func aReadingListThatIsntAListIsUnrecognized() throws {
        var plist = Fixtures.bookmarksFile([])
        var children = plist["Children"] as! [Any]
        var reading = children[3] as! [String: Any]
        reading["Children"] = "oops"
        children[3] = reading
        plist["Children"] = children
        try Fixtures.write(plist: plist, to: home)
        #expect(throws: (any Error).self) { try SafariBookmarks(home: home).read() }
    }

    @Test func protectsSafarisFolderOrJustACopy() {
        let real = SafariBookmarks(home: home)
        #expect(real.protectedFolders.map(\.lastPathComponent) == ["Safari"])
        let copy = SafariBookmarks(file: home.appendingPathComponent("Backups/Bookmarks.plist"))
        #expect(copy.protectedFolders.map(\.lastPathComponent) == ["Bookmarks.plist"])
    }

    @Test func noticesWhenTheFileChanges() throws {
        let file = try Fixtures.write([Fixtures.Entry()], to: home)
        let source = SafariBookmarks(file: file)
        let first = try #require(source.lastChange())
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        #expect(source.lastChange() != first)
        #expect(SafariBookmarks(home: home.appendingPathComponent("nowhere")).lastChange() == nil)
    }

    @Test(arguments: [
        ("https://example.com/a", true), ("http://example.com", true), ("HTTPS://Example.com/x?y=1#z", true),
        ("  https://example.com/trim  ", true), ("ftp://example.com/", false), ("javascript:alert(1)", false),
        ("https://exa mple.com/", false), ("https://example.com/\u{202E}gpj", false), ("https://example.com/\nnext", false),
        ("example.com", false), ("", false), ("mailto:someone@example.com", false),
    ])
    func webAddresses(_ value: String, _ allowed: Bool) {
        #expect((Links.web(value) != nil) == allowed)
    }

    @Test func theRealFileNameAndFolder() {
        #expect(SafariBookmarks(home: URL(fileURLWithPath: "/Users/someone")).file.path == "/Users/someone/Library/Safari/Bookmarks.plist")
        #expect(SafariBookmarks.relativePath == SafariBookmarks.safariFolder + "/Bookmarks.plist")
    }
}
