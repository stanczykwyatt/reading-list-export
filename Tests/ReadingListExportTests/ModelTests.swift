import AppKit
import Foundation
import Testing
@testable import ReadingListCore
@testable import ReadingListExport

@MainActor
@Suite("Model")
struct ModelTests {
    let folder = TestFolder()

    @Test func readsTheReadingList() async throws {
        let model = try await Gallery.model(in: folder)
        #expect(model.status == .ready)
        #expect(model.list.items.count == Gallery.pages.count)
        #expect(model.list.read.count == 6 && model.list.unread.count == 8)
        #expect(model.list.items.first?.title == "How tide pools survive the winter")
    }

    @Test func onlyRereadsWhenSafariChangesIt() async throws {
        let model = try await Gallery.model(in: folder)
        #expect(await model.reload() == false)
        let file = model.source.file
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: file.path)
        #expect(await model.reload() == true)
        #expect(await model.reload(force: true) == true)
    }

    @Test func aMissingFileIsAProblem() async {
        let model = ReadingModel(source: SafariBookmarks(home: folder.sub("Empty")), preferences: testPreferences())
        #expect(model.status == .loading)
        await model.reload()
        #expect(model.status == .problem(.notFound))
        #expect(model.list.items.isEmpty)
    }

    @Test func aLockedFileNeedsAccess() async throws {
        let home = folder.sub("Locked")
        try Gallery.write(to: home)
        let file = SafariBookmarks(home: home).file
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let model = ReadingModel(source: SafariBookmarks(home: home), preferences: testPreferences())
        await model.reload()
        #expect(model.status == .problem(.noPermission))
    }

    @Test func exportsAndCountsWhatsNew() async throws {
        let destination = folder.sub("Vault/Reading")
        let model = try await Gallery.model(in: folder, exportTo: destination)
        #expect(model.pending == Gallery.pages.count)
        var seen: ExportReport?
        model.onExport = { seen = $0 }
        let report = try #require(await model.export(now: Gallery.now))
        #expect(report.newItems == Gallery.pages.count && seen == report)
        #expect(model.pending == 0)
        #expect(model.lastExport?.summary == "Added 14 new pages")
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Reading List.md").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Reading List.html").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Reading List.csv").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Reading List.json").path))
    }

    @Test func exportsWithTheChosenOptions() async throws {
        let destination = folder.sub("Out")
        let model = try await Gallery.model(in: folder, exportTo: destination)
        model.preferences.writesCSV = false
        model.preferences.writesJSON = true
        model.preferences.writesNotes = true
        await model.export(now: Gallery.now)
        let files = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(files.contains("Reading List.json") && files.contains("Pages") && !files.contains("Reading List.csv"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("Pages").path).count == Gallery.pages.count)
    }

    @Test func anExportAskedForMidExportRunsAfterIt() async throws {
        let destination = folder.sub("Twice")
        let model = try await Gallery.model(in: folder, exportTo: destination)
        var reports: [ExportReport] = []
        model.onExport = { reports.append($0) }
        async let first = model.export(now: Gallery.now)
        async let second = model.export(now: Gallery.now)
        let results = await [first, second]
        #expect(results.compactMap { $0 }.count == 1)
        // The one asked for while the first ran follows it.
        for _ in 0..<50 where reports.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(reports.count == 2)
        #expect(reports.last?.newItems == 0)
    }

    @Test func noExportWithoutAFolder() async throws {
        let model = try await Gallery.model(in: folder)
        #expect(await model.export() == nil)
        #expect(model.pending == 0)
    }

    @Test func aDamagedRecordIsExplained() async throws {
        let destination = folder.sub("Damaged")
        try Data("nope".utf8).write(to: destination.appendingPathComponent(Exporter.recordName))
        let model = try await Gallery.model(in: folder, exportTo: destination)
        #expect(model.exportProblem?.contains("can't be read") == true)
        #expect(await model.export() == nil)
        #expect(model.exportProblem != nil)
    }

    @Test func choosingAFolderRemembersIt() async throws {
        let model = try await Gallery.model(in: folder)
        await model.setFolder(folder.sub("Chosen"))
        #expect(model.folder?.url.lastPathComponent == "Chosen")
        #expect(model.pending == Gallery.pages.count)
    }

    @Test func savesABookmarksFile() async throws {
        let model = try await Gallery.model(in: folder)
        let file = folder.url.appendingPathComponent("Reading List.html")
        #expect(model.saveBookmarks(to: file) == nil)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("How tide pools survive the winter"))
        let inside = model.source.file.deletingLastPathComponent().appendingPathComponent("x.html")
        #expect(model.saveBookmarks(to: inside)?.contains("outside Safari") == true)
    }

    @Test func copiesLinks() async throws {
        let model = try await Gallery.model(in: folder)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(model.copy([model.list.items[0]], to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "https://tidewatch.example.com/winter-pools")
        #expect(model.copy(Array(model.list.items.prefix(2)), to: pasteboard))
        #expect(pasteboard.string(forType: .string)?.hasPrefix("- [How tide pools survive the winter](<https://tidewatch.example.com/winter-pools>)\n- [A field guide") == true)
        #expect(!model.copy([], to: pasteboard))
    }

    @Test func preferencesHaveSensibleDefaults() {
        let preferences = testPreferences()
        #expect(preferences.options == ExportOptions())
        #expect(!preferences.exportsAutomatically && !preferences.launchedBefore && preferences.lastExport == nil)
        preferences.lastExport = (Gallery.now, "Nothing new")
        #expect(preferences.lastExport?.summary == "Nothing new")
    }
}
