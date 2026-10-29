import AppKit
import Foundation
@testable import ReadingListCore
@testable import ReadingListExport

/// A throwaway folder that's removed when the test ends.
final class TestFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingListAppTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func sub(_ name: String) -> URL {
        let sub = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        return sub
    }
}

/// Settings in a suite of their own, so tests never touch the app's real ones.
func testPreferences() -> Preferences {
    let name = "ReadingListExportTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return Preferences(defaults: defaults)
}

/// A made-up Reading List: a bookmarks file shaped like Safari's own, in a throwaway folder.
/// Every page, site and sentence here is invented.
enum Gallery {
    struct Page {
        var title: String
        var url: String
        var site: String?
        var daysAgo: Double
        /// Days since you read it, or nil if it's unread.
        var readDaysAgo: Double?
        var preview: String
    }

    static let now = Date(timeIntervalSince1970: 1_777_560_060)

    static let pages: [Page] = [
        Page(title: "How tide pools survive the winter", url: "https://tidewatch.example.com/winter-pools", site: "Tide Watch", daysAgo: 0.2,
             preview: "Every January the pools freeze at the edges, and yet the anemones are back by March. Here's what happens under the ice."),
        Page(title: "A field guide to city lichens", url: "https://lichens.example.org/city-guide", site: "Lichen Society", daysAgo: 1.4,
             preview: "Crusty, leafy and shrubby: the three shapes to learn first, and the walls where you'll find all of them."),
        Page(title: "Why trains run late in the snow", url: "https://rails.example.net/snow-delays", daysAgo: 2.1, readDaysAgo: 1,
             preview: "Points freeze, wheels slip and timetables were never written for it. A signal engineer explains the knock-on."),
        Page(title: "The quiet economics of public libraries", url: "https://ledger.example.com/libraries", site: "The Ledger", daysAgo: 3,
             preview: "What a library card is worth, measured in books, heating and the internet, for a town of forty thousand."),
        Page(title: "Learning to sharpen a kitchen knife", url: "https://whetstone.example.com/basics", daysAgo: 4.5, readDaysAgo: 4,
             preview: "Hold the angle, count the strokes, and stop before you think you should. Three stones are plenty."),
        Page(title: "What sleep does to memory, in plain words", url: "https://brainnotes.example.org/sleep-memory", site: "Brain Notes", daysAgo: 6,
             preview: "During deep sleep the day's memories are replayed, and the ones that matter get moved somewhere sturdier."),
        Page(title: "Building a bookshelf with no screws", url: "https://joinery.example.com/no-screws", daysAgo: 8, readDaysAgo: 7,
             preview: "Wedged through-tenons hold it together, and it comes apart flat when you move."),
        Page(title: "Ferry timetables, explained", url: "https://harbor.example.net/ferries", site: "Harbor Weekly", daysAgo: 11,
             preview: "Tides, crew changes and the one dock that only works at high water."),
        Page(title: "Notes on running a small reading group", url: "https://margins.example.com/reading-group", daysAgo: 15, readDaysAgo: 12,
             preview: "Six people, one short book a month, and a rule that nobody has to finish it."),
        Page(title: "The case for walking the long way home", url: "https://slowroutes.example.org/long-way", daysAgo: 19,
             preview: "Ten extra minutes, a different street, and the small things you start noticing by the second week."),
        Page(title: "Measuring rainfall with a coffee can", url: "https://backyard.example.com/rain-gauge", daysAgo: 26, readDaysAgo: 20,
             preview: "Straight sides matter more than size. Check it at the same hour every morning."),
        Page(title: "How bridges are inspected", url: "https://spans.example.net/inspection", site: "Spans", daysAgo: 33,
             preview: "Ropes, drones and a hammer that tells you more than any sensor."),
        Page(title: "Repairing a bicycle wheel at home", url: "https://spokes.example.com/truing", daysAgo: 41, readDaysAgo: 30,
             preview: "A zip tie on the frame is all the truing stand you need for a first try."),
        Page(title: "A short history of the paperback", url: "https://inkwell.example.org/paperback", daysAgo: 58,
             preview: "Cheap, light and sold at train stations: how a small format changed who got to read."),
    ]

    /// Writes the Reading List into `home`, the way Safari lays it out.
    static func write(to home: URL, now: Date = now) throws {
        let entries: [[String: Any]] = pages.enumerated().map { index, page in
            var reading: [String: Any] = ["DateAdded": now.addingTimeInterval(-page.daysAgo * 86400), "PreviewText": page.preview]
            if let read = page.readDaysAgo { reading["DateLastViewed"] = now.addingTimeInterval(-read * 86400) }
            var local: [String: Any] = ["neverFetchedMetadata": false]
            if let site = page.site { local["siteName"] = site }
            return [
                "WebBookmarkType": "WebBookmarkTypeLeaf", "WebBookmarkUUID": "PAGE-\(index)", "URLString": page.url,
                "URIDictionary": ["title": page.title], "ReadingList": reading, "ReadingListNonSync": local,
            ]
        }
        let root: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList", "Title": "", "WebBookmarkFileVersion": 1,
            "Children": [
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar", "Children": []],
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "com.apple.ReadingList", "Children": entries],
            ],
        ]
        let safari = home.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: safari.appendingPathComponent("Bookmarks.plist"))
    }

    /// A model reading the made-up Reading List, already loaded.
    @MainActor
    static func model(in folder: TestFolder, exportTo: URL? = nil) async throws -> ReadingModel {
        let home = folder.sub("Home")
        try write(to: home)
        let model = ReadingModel(
            source: SafariBookmarks(home: home), preferences: testPreferences(),
            folder: exportTo.map { ExportFolder(url: $0, scoped: false) }
        )
        await model.reload()
        return model
    }
}
