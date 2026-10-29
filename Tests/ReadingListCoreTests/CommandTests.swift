import Foundation
import Testing
@testable import ReadingListCore

@Suite("Command line")
struct CommandTests {
    let folder = Fixtures.Folder()

    private func run(_ arguments: [String]) -> (status: Int32, out: String, err: String) {
        var out: [String] = [], err: [String] = []
        let status = Command.run(
            arguments, home: folder.url, workingDirectory: folder.url, renderer: Fixtures.renderer, now: Fixtures.date,
            out: { out.append($0) }, err: { err.append($0) }
        )
        return (status, out.joined(separator: "\n"), err.joined(separator: "\n"))
    }

    private func writeLibrary() throws {
        try Fixtures.write([
            Fixtures.Entry(uuid: "U1", url: "https://tidewatch.example.com/a", title: "How tide pools survive winter", added: Fixtures.date.addingTimeInterval(-86400)),
            Fixtures.Entry(uuid: "U2", url: "https://lichens.example.org/guide", title: "A field guide to lichens", added: Fixtures.date.addingTimeInterval(-4 * 86400), viewed: Fixtures.date),
        ], to: folder.url)
    }

    @Test func parses() throws {
        #expect(try Command.parse([]).0 == .help)
        #expect(try Command.parse(["list"]).0 == .list(filter: .all, json: false, limit: nil))
        #expect(try Command.parse(["list", "--unread", "--limit", "5"]).0 == .list(filter: .unread, json: false, limit: 5))
        #expect(try Command.parse(["list", "--read", "--json"]).0 == .list(filter: .read, json: true, limit: nil))
        #expect(try Command.parse(["bookmarks", "--bookmarks-file", "~/b.plist"]) == (.bookmarks, "~/b.plist"))
        let (export, _) = try Command.parse(["export", "out", "--no-csv", "--json", "--notes"])
        #expect(export == .export(folder: "out", options: ExportOptions(csv: false, json: true, notes: true)))
        #expect(try Command.parse(["export", "out", "--version"]).0 == .version)
    }

    @Test(arguments: [
        ["list", "extra"], ["list", "--limit"], ["list", "--limit", "0"], ["list", "--unread", "--read"], ["bookmarks", "x"],
        ["export"], ["export", "a", "b"], ["export", "a", "--opml"], ["nonsense"], ["list", "--notes"],
    ])
    func refusesMistakes(_ arguments: [String]) {
        #expect(run(arguments).status == 2)
    }

    @Test func helpAndVersion() {
        #expect(run(["--help"]).out.contains("reading-list-export export <folder>"))
        #expect(run(["--version"]).out == "reading-list-export \(Command.toolVersion)")
    }

    @Test func listsPages() throws {
        try writeLibrary()
        let result = run(["list"])
        #expect(result.status == 0)
        #expect(result.out.contains("2026-04-29  unread  How tide pools survive winter\n            https://tidewatch.example.com/a"))
        #expect(result.out.contains("read    A field guide to lichens"))
        #expect(!run(["list", "--unread"]).out.contains("lichens"))
        #expect(run(["list", "--read", "--limit", "1"]).out.contains("lichens"))
    }

    @Test func listsAsJSON() throws {
        try writeLibrary()
        let result = run(["list", "--json"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
        #expect((object["items"] as? [Any])?.count == 2)
    }

    @Test func anEmptyList() throws {
        try Fixtures.write([], to: folder.url)
        #expect(run(["list"]).out == "Your Reading List is empty.")
    }

    @Test func printsTheBookmarksFile() throws {
        try writeLibrary()
        let result = run(["bookmarks"])
        #expect(result.status == 0 && result.out.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        #expect(result.out.contains("TOREAD=\"1\">How tide pools survive winter</A>"))
    }

    @Test func exportsToAFolder() throws {
        try writeLibrary()
        let result = run(["export", "~/Notes/Reading", "--json"])
        #expect(result.status == 0)
        #expect(result.out.hasPrefix("Added 2 new pages."))
        #expect(result.out.contains("  + Reading List.json"))
        #expect(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("Notes/Reading/Reading List.md").path))
        #expect(run(["export", "Notes/Reading"]).out.hasPrefix("Nothing new."))
    }

    @Test func exportsNotesAndSaysWhatWasLeftOut() throws {
        try Fixtures.write([Fixtures.Entry(uuid: "U1"), Fixtures.Entry(url: "javascript:void(0)")], to: folder.url)
        let result = run(["export", "Out", "--notes", "--no-csv"])
        #expect(result.status == 0)
        #expect(result.out.contains("  + Pages/How tide pools survive winter.md"))
        #expect(result.out.contains("  … Left out 1 entry that wasn't a web page."))
        #expect(!result.out.contains("Reading List.csv"))
        #expect(run(["bookmarks"]).err == "Left out 1 entry that wasn't a web page.")
        #expect(Describe.skipped(3) == "3 entries that weren't web pages")
    }

    @Test func neverExportsIntoSafari() throws {
        try writeLibrary()
        let result = run(["export", "Library/Safari/Export"])
        #expect(result.status == 1 && result.err.contains("outside Safari's folder"))
        // Nor beside a copy being read, into the real Safari folder.
        let backup = folder.url.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder.url.appendingPathComponent("Library/Safari/Bookmarks.plist"), to: backup.appendingPathComponent("Bookmarks.plist"))
        #expect(run(["export", "Library/Safari", "--bookmarks-file", "Backup/Bookmarks.plist"]).status == 1)
        #expect(run(["export", "Out", "--bookmarks-file", "Backup/Bookmarks.plist"]).status == 0)
    }

    @Test func explainsMissingAccess() throws {
        let file = try Fixtures.write([Fixtures.Entry()], to: folder.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let result = run(["list"])
        #expect(result.status == 1 && result.err.contains("Full Disk Access"))
    }

    @Test func explainsAMissingFile() {
        let result = run(["list"])
        #expect(result.status == 1 && result.err.contains("No Safari bookmarks"))
    }

    @Test func titlesCantSendTerminalCommands() throws {
        try Fixtures.write([Fixtures.Entry(title: "Evil\u{1B}]52;c;bWFkZQ==\u{07}title")], to: folder.url)
        let result = run(["list"])
        #expect(!result.out.contains("\u{1B}") && !result.out.contains("\u{07}"))
        #expect(result.out.contains("Evil]52;c;bWFkZQ==title"))
    }
}

@Suite("Search and wording")
struct SearchTests {
    let items = Fixtures.list.items

    @Test func findsByAnyWord() {
        #expect(Search.run("lichen", in: items).map(\.id) == ["A2"])
        #expect(Search.run("SNOW trains", in: items).map(\.id) == ["A3"])
        #expect(Search.run("anemones", in: items).map(\.id) == ["A1", "A2"])
        #expect(Search.run("rails.example", in: items).map(\.id) == ["A3"])
        #expect(Search.run("nothing like this", in: items).isEmpty)
        #expect(Search.run("", in: items).map(\.id) == ["A1", "A2", "A3"])
    }

    @Test func filtersByReadOrNot() {
        #expect(Search.run("", filter: .unread, in: items).map(\.id) == ["A1", "A3"])
        #expect(Search.run("", filter: .read, in: items).map(\.id) == ["A2"])
        #expect(Search.run("tide", filter: .read, in: items).isEmpty)
    }

    @Test func ignoresAccents() {
        let café = Fixtures.item("C1", title: "Le café des marées")
        #expect(Search.run("cafe marees", in: [café]).count == 1)
    }

    @Test func highlights() {
        let text = "Tide pools and tide charts"
        #expect(Search.ranges(of: "tide", in: text).map { text.distance(from: text.startIndex, to: $0.lowerBound) } == [0, 15])
    }

    @Test func relativeTimes() {
        let now = Fixtures.date
        #expect(Describe.relative(now, now: now) == "just now")
        #expect(Describe.relative(now.addingTimeInterval(-300), now: now) == "5 min ago")
        #expect(Describe.relative(now.addingTimeInterval(-7200), now: now) == "2 hr ago")
        #expect(Describe.relative(now.addingTimeInterval(-86400), now: now) == "yesterday")
        #expect(Describe.relative(now.addingTimeInterval(-86400 * 10), now: now) == "10 days ago")
        #expect(Describe.relative(now.addingTimeInterval(-86400 * 120), now: now) == "4 months ago")
        #expect(Describe.relative(now.addingTimeInterval(-86400 * 800), now: now) == "2 years ago")
    }

    @Test func totalsAndPaths() {
        #expect(Describe.totals(Fixtures.list) == "2 unread · 1 read")
        #expect(Describe.totals(ReadingList()) == "Reading List is empty")
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(Describe.path(home.appendingPathComponent("Notes/Reading"), home: home) == "~/Notes/Reading")
        #expect(Describe.path(URL(fileURLWithPath: "/Volumes/Disk"), home: home) == "/Volumes/Disk")
    }

    @Test func summaries() {
        var report = ExportReport()
        #expect(Describe.summary(report) == "Nothing new")
        report.written = ["Reading List.md"]
        #expect(Describe.summary(report) == "Updated 1 file")
        report.failed = [.init(file: "x", reason: "y")]
        #expect(Describe.summary(report) == "Updated 1 file, 1 failed")
    }

    @Test func everyProblemHasWords() {
        for error in [LibraryError.notFound, .noPermission, .unrecognized("Odd file.")] {
            #expect(!Describe.problem(error).isEmpty)
        }
        for error in [ExportError.insideLibrary, .unreadableRecord, .newerRecord, .busy, .cannotWrite("Disk full.")] {
            #expect(!Describe.problem(error).isEmpty)
        }
    }
}
