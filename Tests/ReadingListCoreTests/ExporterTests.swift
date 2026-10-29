import Foundation
import Testing
@testable import ReadingListCore

@Suite("Exporting")
struct ExporterTests {
    let folder = Fixtures.Folder()
    var destination: URL { folder.url.appendingPathComponent("Vault/Reading", isDirectory: true) }

    private func exporter(_ options: ExportOptions = ExportOptions(renderer: Fixtures.renderer)) -> Exporter {
        Exporter(destination: destination, options: options)
    }

    private func files(_ sub: String = "") throws -> [String] {
        // The lock file is always there once an export has run, and never holds anything.
        try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent(sub).path).filter { $0 != ".reading-list-export.lock" }.sorted()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: destination.appendingPathComponent(path), encoding: .utf8)
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: destination.appendingPathComponent(path))
    }

    @Test func exportsEverything() throws {
        let report = try exporter().export(Fixtures.list, now: Fixtures.date)
        #expect(report.newItems == 3 && report.newlyRead == 0)
        #expect(try files() == [".reading-list-export.json", "Reading List.csv", "Reading List.html", "Reading List.md"])
        #expect(Set(report.written) == ["Reading List.md", "Reading List.html", "Reading List.csv"])
        #expect(try read("Reading List.md").contains("Why trains run late in the snow"))
        #expect(Describe.summary(report) == "Added 3 new pages")
    }

    @Test func everyFormatCanBeTurnedOnOrOff() throws {
        let options = ExportOptions(markdown: false, bookmarks: false, csv: false, json: true, notes: true, renderer: Fixtures.renderer)
        _ = try exporter(options).export(Fixtures.list, now: Fixtures.date)
        #expect(try files() == [".reading-list-export.json", "Pages", "Reading List.json"])
        #expect(try files("Pages") == ["A field guide to lichens.md", "How tide pools survive winter.md", "Why trains run late in the snow.md"])
    }

    @Test func aRerunWithNothingNewWritesNothing() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        let report = try exporter().export(Fixtures.list, now: Fixtures.date.addingTimeInterval(3600))
        #expect(report.written.isEmpty && report.newItems == 0)
        #expect(Describe.summary(report) == "Nothing new")
    }

    @Test func aRerunAddsOnlyWhatsNew() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        var next = Fixtures.list
        next.items.append(Fixtures.item("A4", title: "Ferry timetables, explained", daysAgo: 0.5))
        #expect(try exporter().newItems(next) == 1)
        let report = try exporter().export(next, now: Fixtures.date)
        #expect(report.newItems == 1)
        #expect(Set(report.written) == ["Reading List.md", "Reading List.html", "Reading List.csv"])
        #expect(try read("Reading List.csv").contains("Ferry timetables, explained"))
        #expect(try exporter().newItems(next) == 0)
    }

    @Test func readingAPageUpdatesIt() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        var next = Fixtures.list
        let index = next.items.firstIndex { $0.id == "A1" }!
        next.items[index].read = true
        next.items[index].viewed = Fixtures.date
        let report = try exporter().export(next, now: Fixtures.date)
        #expect(report.newlyRead == 1 && report.newItems == 0)
        #expect(Describe.summary(report) == "1 newly read")
        #expect(try read("Reading List.md").contains("- [x] [How tide pools survive winter]"))
        #expect(try read("Reading List.csv").components(separatedBy: "\"Archive\"").count == 3)
    }

    @Test func pagesYouRemoveFromSafariStay() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        var next = Fixtures.list
        next.items.removeAll { $0.id == "A2" }
        let later = Fixtures.date.addingTimeInterval(86400)
        _ = try exporter().export(next, now: later)
        let note = try read("Reading List.md")
        #expect(note.contains("A field guide to lichens") && note.contains("removed from Safari 2026-05-01"))
        #expect(try read("Reading List.html").contains("lichens.example.org"))
        // It keeps the first date it was found gone.
        _ = try exporter().export(next, now: later.addingTimeInterval(86400 * 5))
        #expect(try read("Reading List.md").contains("removed from Safari 2026-05-01"))
        // And comes back if you add it again.
        _ = try exporter().export(Fixtures.list, now: later)
        #expect(!(try read("Reading List.md")).contains("removed from Safari"))
    }

    @Test func anEmptyListMarksNothingRemoved() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        let report = try exporter().export(ReadingList(), now: Fixtures.date)
        #expect(report.heldBack)
        #expect(!(try read("Reading List.md")).contains("removed from Safari"))
    }

    @Test func aListMuchShorterThanBeforeMarksNothingRemoved() throws {
        let many = ReadingList(items: (1...10).map { Fixtures.item("M\($0)", daysAgo: Double($0)) })
        _ = try exporter().export(many, now: Fixtures.date)
        let report = try exporter().export(ReadingList(items: Array(many.items.prefix(4))), now: Fixtures.date)
        #expect(report.heldBack)
        #expect(!(try read("Reading List.md")).contains("removed from Safari"))
        let fewer = try exporter().export(ReadingList(items: Array(many.items.prefix(6))), now: Fixtures.date)
        #expect(!fewer.heldBack)
        #expect(try read("Reading List.md").components(separatedBy: "removed from Safari").count - 1 == 4)
    }

    @Test func aShortListIsBelievedAfterADay() throws {
        let many = ReadingList(items: (1...10).map { Fixtures.item("M\($0)", daysAgo: Double($0)) })
        _ = try exporter().export(many, now: Fixtures.date)
        let short = ReadingList(items: Array(many.items.prefix(3)))
        #expect(try exporter().export(short, now: Fixtures.date).heldBack)
        #expect(try exporter().export(short, now: Fixtures.date.addingTimeInterval(3600)).heldBack)
        let report = try exporter().export(short, now: Fixtures.date.addingTimeInterval(86400))
        #expect(!report.heldBack)
        #expect(try read("Reading List.md").components(separatedBy: "removed from Safari").count - 1 == 7)
        #expect(try exporter().loadRecord().shortSince == nil)
    }

    @Test func aListThatFillsBackInStartsTheWaitOver() throws {
        let many = ReadingList(items: (1...10).map { Fixtures.item("M\($0)", daysAgo: Double($0)) })
        _ = try exporter().export(many, now: Fixtures.date)
        _ = try exporter().export(ReadingList(), now: Fixtures.date)
        _ = try exporter().export(many, now: Fixtures.date.addingTimeInterval(3600))
        #expect(try exporter().loadRecord().shortSince == nil)
        #expect(try exporter().export(ReadingList(), now: Fixtures.date.addingTimeInterval(86400 * 2)).heldBack)
    }

    @Test func aPageUnderANewIDKeepsItsOldOne() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        var next = Fixtures.list
        let index = next.items.firstIndex { $0.id == "A2" }!
        next.items[index].id = "NEW-ID"
        let report = try exporter().export(next, now: Fixtures.date)
        #expect(report.newItems == 0)
        let record = try exporter().loadRecord()
        #expect(record.items["NEW-ID"] == nil && record.items["A2"]?.inSafari == true)
    }

    @Test func twoPagesWithOneAddressAreNotMerged() throws {
        let one = Fixtures.item("D1", url: "https://same.example.com/")
        _ = try exporter().export(ReadingList(items: [one]), now: Fixtures.date)
        let report = try exporter().export(ReadingList(items: [one, Fixtures.item("D2", url: "https://same.example.com/")]), now: Fixtures.date)
        #expect(report.newItems == 1)
        #expect(try exporter().loadRecord().items.count == 2)
    }

    @Test func anEditedFileIsKeptAndSaidOnce() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        try write("My own notes\n", to: "Reading List.md")
        var next = Fixtures.list
        next.items.append(Fixtures.item("A4", daysAgo: 0))
        let report = try exporter().export(next, now: Fixtures.date)
        #expect(report.kept == ["Reading List.md"])
        #expect(try read("Reading List.md") == "My own notes\n")
        #expect(Describe.summary(report) == "Added 1 new page, kept 1 edited file")
        #expect(try exporter().export(next, now: Fixtures.date).kept.isEmpty)
        next.items.append(Fixtures.item("A5", daysAgo: 0))
        #expect(try exporter().export(next, now: Fixtures.date).kept == ["Reading List.md"])
    }

    @Test func aFileThatCantBeReadIsAFailureNotAnEdit() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        let file = destination.appendingPathComponent("Reading List.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        var next = Fixtures.list
        next.items.append(Fixtures.item("A4", daysAgo: 0))
        let report = try exporter().export(next, now: Fixtures.date)
        #expect(report.kept.isEmpty)
        #expect(report.failed.map(\.file) == ["Reading List.md"])
    }

    @Test func startingOverTakesBackFilesThatHaventChanged() throws {
        _ = try exporter(ExportOptions(notes: true, renderer: Fixtures.renderer)).export(Fixtures.list, now: Fixtures.date)
        try FileManager.default.moveItem(at: destination.appendingPathComponent(Exporter.recordName), to: folder.url.appendingPathComponent("old.json"))
        let report = try exporter(ExportOptions(notes: true, renderer: Fixtures.renderer)).export(Fixtures.list, now: Fixtures.date)
        #expect(report.written.isEmpty && report.newItems == 3)
        #expect(try files() == [".reading-list-export.json", "Pages", "Reading List.csv", "Reading List.html", "Reading List.md"])
        #expect(try files("Pages").count == 3)
    }

    @Test func aLinkedLockFileIsRefused() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let elsewhere = folder.url.appendingPathComponent("elsewhere.txt")
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent(".reading-list-export.lock"), withDestinationURL: elsewhere)
        #expect(throws: (any Error).self) { try exporter().export(Fixtures.list) }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.path))
    }

    @Test func aDeletedFileComesBackButADeletedNoteDoesnt() throws {
        let options = ExportOptions(notes: true, renderer: Fixtures.renderer)
        _ = try exporter(options).export(Fixtures.list, now: Fixtures.date)
        try FileManager.default.removeItem(at: destination.appendingPathComponent("Reading List.csv"))
        try FileManager.default.removeItem(at: destination.appendingPathComponent("Pages/A field guide to lichens.md"))
        let report = try exporter(options).export(Fixtures.list, now: Fixtures.date)
        #expect(report.written == ["Reading List.csv"])
        #expect(try files("Pages").count == 2)
    }

    @Test func notesWithOneTitleGetTheirOwnNames() throws {
        let options = ExportOptions(markdown: false, bookmarks: false, csv: false, notes: true, renderer: Fixtures.renderer)
        let list = ReadingList(items: [Fixtures.item("T1", title: "Same", daysAgo: 5), Fixtures.item("T2", title: "same", daysAgo: 1)])
        _ = try exporter(options).export(list, now: Fixtures.date)
        #expect(try files("Pages") == ["Same.md", "same (2).md"])
        #expect(try read("Pages/Same.md").contains("reading-list-id: \"T1\""))
    }

    @Test func anUnEditedNoteFollowsTheReadStatus() throws {
        let options = ExportOptions(markdown: false, bookmarks: false, csv: false, notes: true, renderer: Fixtures.renderer)
        _ = try exporter(options).export(Fixtures.list, now: Fixtures.date)
        var next = Fixtures.list
        let index = next.items.firstIndex { $0.id == "A1" }!
        next.items[index].read = true
        let report = try exporter(options).export(next, now: Fixtures.date)
        #expect(report.written == ["Pages/How tide pools survive winter.md"])
        #expect(try read("Pages/How tide pools survive winter.md").contains("read: true"))
    }

    @Test func aRemovedPageIsntCountedAgainstTheNextList() throws {
        let many = ReadingList(items: (1...8).map { Fixtures.item("M\($0)", daysAgo: Double($0)) })
        _ = try exporter().export(many, now: Fixtures.date)
        // Half gone is still a real change, and those four are marked.
        let half = ReadingList(items: Array(many.items.prefix(4)))
        #expect(!(try exporter().export(half, now: Fixtures.date)).heldBack)
        // The next run compares against the four still in Safari, not all eight.
        #expect(!(try exporter().export(ReadingList(items: Array(half.items.prefix(3))), now: Fixtures.date)).heldBack)
    }

    @Test func aFileOfYoursIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try write("mine", to: "Reading List.md")
        let report = try exporter().export(Fixtures.list, now: Fixtures.date)
        #expect(try read("Reading List.md") == "mine")
        #expect(report.written.contains("Reading List (2).md"))
    }

    @Test func neverWritesInsideSafari() throws {
        let safari = folder.url.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        #expect(throws: ExportError.insideLibrary) {
            try Exporter(destination: safari.appendingPathComponent("Export")).export(Fixtures.list, protected: [safari])
        }
        // Not through a link either.
        let link = folder.url.appendingPathComponent("Shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: safari)
        #expect(throws: ExportError.insideLibrary) {
            try Exporter(destination: link).export(Fixtures.list, protected: [safari])
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: safari.path).isEmpty)
    }

    @Test func aFolderLinkedIntoSafariIsntWrittenTo() throws {
        let safari = folder.url.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        let options = ExportOptions(markdown: false, bookmarks: false, csv: false, notes: true, renderer: Fixtures.renderer)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent("Pages"), withDestinationURL: safari)
        let report = try exporter(options).export(Fixtures.list, protected: [safari], now: Fixtures.date)
        #expect(report.failed.count == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: safari.path).isEmpty)
    }

    @Test func oneExportAtATime() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let lock = destination.appendingPathComponent(".reading-list-export.lock")
        let result: Result<ExportReport?, Error> = Result {
            try FileLock.run(at: lock) {
                try exporter().export(Fixtures.list, now: Fixtures.date)
            }
        }
        if case .failure(let error) = result {
            #expect(error as? ExportError == .busy)
        } else {
            Issue.record("A second export ran while the first held the lock.")
        }
    }

    @Test func aDamagedRecordStopsTheExport() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try write("{ not json", to: Exporter.recordName)
        #expect(throws: ExportError.unreadableRecord) { try exporter().export(Fixtures.list) }
        #expect(throws: ExportError.unreadableRecord) { try exporter().newItems(Fixtures.list) }
    }

    @Test func aNewerRecordStopsTheExport() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try write("{\"version\": 99}", to: Exporter.recordName)
        #expect(throws: ExportError.newerRecord) { try exporter().export(Fixtures.list) }
    }

    @Test func aRecordPointingOutsideIsRefused() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        let record = try read(Exporter.recordName).replacingOccurrences(of: "\"path\" : \"Reading List.md\"", with: "\"path\" : \"../../escape.md\"")
        try write(record, to: Exporter.recordName)
        #expect(throws: ExportError.unreadableRecord) { try exporter().export(Fixtures.list) }
    }

    @Test func aRecordWithAnUnsafeLinkIsRefused() throws {
        _ = try exporter().export(Fixtures.list, now: Fixtures.date)
        let record = try read(Exporter.recordName).replacingOccurrences(of: "https://rails.example.net/snow", with: "javascript:alert(1)")
        try write(record, to: Exporter.recordName)
        #expect(throws: ExportError.unreadableRecord) { try exporter().export(Fixtures.list) }
    }

    @Test(arguments: [("Reading List.md", true), ("Pages/A.md", true), ("../x", false), ("/etc/x", false), (".hidden", false), ("a/b/c", false), ("a\\b", false)])
    func safePaths(_ path: String, _ safe: Bool) {
        #expect(Exporter.isSafePath(path) == safe)
    }

    @Test func savesABookmarksFileOnItsOwn() throws {
        let file = folder.url.appendingPathComponent("Reading List.html")
        try Exporter.saveBookmarks(Fixtures.list, to: file, protected: [], renderer: Fixtures.renderer)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("TOREAD"))
        let safari = folder.url.appendingPathComponent("Library/Safari", isDirectory: true)
        #expect(throws: ExportError.insideLibrary) {
            try Exporter.saveBookmarks(Fixtures.list, to: safari.appendingPathComponent("x.html"), protected: [safari])
        }
    }

    @Test func skippedEntriesAreReported() throws {
        let report = try exporter().export(ReadingList(items: Fixtures.list.items, skipped: 2), now: Fixtures.date)
        #expect(report.skipped == 2)
    }

    @Test func aReadOnlyFolderFailsCleanly() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
        #expect(throws: (any Error).self) { try exporter().export(Fixtures.list) }
    }
}
