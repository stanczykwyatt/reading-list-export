import Foundation
@testable import ReadingListCore

/// Made-up Reading Lists and bookmarks files for the tests. Every page and site here is invented.
enum Fixtures {
    /// 2026-04-30 14:41 UTC.
    static let date = Date(timeIntervalSince1970: 1_777_560_060)
    static let renderer = Renderer(timeZone: TimeZone(identifier: "America/Chicago")!, locale: Locale(identifier: "en_US"))

    /// A throwaway folder that's removed when the test ends.
    final class Folder {
        let url: URL

        init() {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingListTests-\(UUID().uuidString)", isDirectory: true)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func item(
        _ id: String = "A1", title: String = "How tide pools survive winter", url: String? = nil, site: String? = nil,
        preview: String? = "Every January the pools freeze at the edges, and yet the anemones are back by March.",
        daysAgo: Double? = 3, read: Bool = false, viewedDaysAgo: Double? = nil, removed: Date? = nil
    ) -> Item {
        Item(
            id: id, url: url ?? "https://tidewatch.example.com/\(id.lowercased())", title: title, siteName: site, preview: preview,
            added: daysAgo.map { date.addingTimeInterval(-$0 * 86400) }, read: read,
            viewed: read ? viewedDaysAgo.map { date.addingTimeInterval(-$0 * 86400) } : nil, removed: removed
        )
    }

    static var list: ReadingList {
        ReadingList(items: [
            item("A1", daysAgo: 1),
            item("A2", title: "A field guide to lichens", url: "https://lichens.example.org/guide", site: "Lichen Society", daysAgo: 4, read: true, viewedDaysAgo: 2),
            item("A3", title: "Why trains run late in the snow", url: "https://rails.example.net/snow", preview: nil, daysAgo: 9),
        ])
    }

    // MARK: Bookmarks files

    /// One saved page, the way Safari writes it into its bookmarks file.
    struct Entry {
        var uuid: String? = UUID().uuidString
        var url: String? = "https://tidewatch.example.com/a"
        var title: String? = "How tide pools survive winter"
        var added: Date? = Fixtures.date.addingTimeInterval(-86400)
        var viewed: Date?
        var preview: String? = "Every January the pools freeze at the edges."
        var siteName: String?
        var type = "WebBookmarkTypeLeaf"

        var dictionary: [String: Any] {
            var entry: [String: Any] = ["WebBookmarkType": type]
            if let uuid { entry["WebBookmarkUUID"] = uuid }
            if let url { entry["URLString"] = url }
            if let title { entry["URIDictionary"] = ["title": title] }
            var reading: [String: Any] = [:]
            if let added { reading["DateAdded"] = added; reading["DateLastFetched"] = added }
            if let viewed { reading["DateLastViewed"] = viewed }
            if let preview { reading["PreviewText"] = preview }
            entry["ReadingList"] = reading
            var local: [String: Any] = ["neverFetchedMetadata": false]
            if let siteName { local["siteName"] = siteName }
            entry["ReadingListNonSync"] = local
            entry["Sync"] = ["ServerID": "made-up-server-id", "Key": "made-up"]
            return entry
        }
    }

    /// A whole bookmarks file: the history proxy, a Favorites bar and menu with bookmarks of
    /// their own, which must never be read, and the Reading List.
    static func bookmarksFile(_ entries: [Entry], readingList: Bool = true) -> [String: Any] {
        var children: [Any] = [
            ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History", "WebBookmarkIdentifier": "History", "WebBookmarkUUID": UUID().uuidString],
            [
                "WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar", "WebBookmarkUUID": UUID().uuidString,
                "Children": [
                    ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://favorite.example.com/", "URIDictionary": ["title": "A favorite, not a page to read"], "WebBookmarkUUID": UUID().uuidString],
                ],
            ],
            ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksMenu", "WebBookmarkUUID": UUID().uuidString, "Children": []],
        ]
        if readingList {
            children.append([
                "WebBookmarkType": "WebBookmarkTypeList", "Title": "com.apple.ReadingList", "ShouldOmitFromUI": true,
                "WebBookmarkUUID": UUID().uuidString, "Children": entries.map(\.dictionary),
            ])
        }
        return ["WebBookmarkType": "WebBookmarkTypeList", "Title": "", "WebBookmarkFileVersion": 1, "WebBookmarkUUID": "Root", "Children": children]
    }

    /// Writes a bookmarks file as Safari does, in binary form, and returns where.
    @discardableResult
    static func write(_ entries: [Entry], to folder: URL, readingList: Bool = true, format: PropertyListSerialization.PropertyListFormat = .binary) throws -> URL {
        try write(plist: bookmarksFile(entries, readingList: readingList), to: folder, format: format)
    }

    @discardableResult
    static func write(plist: [String: Any], to folder: URL, format: PropertyListSerialization.PropertyListFormat = .binary) throws -> URL {
        let safari = folder.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        let file = safari.appendingPathComponent("Bookmarks.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0).write(to: file)
        return file
    }
}
