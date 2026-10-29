import Foundation
import Testing
@testable import ReadingListCore

@Suite("Pages")
struct ReadingListTests {
    @Test func aPagesSite() {
        #expect(Fixtures.item(url: "https://www.Lichens.example.org/a").site == "lichens.example.org")
        #expect(Fixtures.item(url: "https://lichens.example.org/a", site: "Lichen Society").site == "Lichen Society")
    }

    @Test func newestFirstThenUndated() {
        let list = ReadingList(items: [
            Fixtures.item("U2", daysAgo: nil), Fixtures.item("OLD", daysAgo: 30), Fixtures.item("U1", daysAgo: nil), Fixtures.item("NEW", daysAgo: 1),
        ])
        #expect(list.items.map(\.id) == ["NEW", "OLD", "U1", "U2"])
    }

    @Test func readAndUnread() {
        let list = Fixtures.list
        #expect(list.unread.map(\.id) == ["A1", "A3"] && list.read.map(\.id) == ["A2"])
        #expect(list.item("A2")?.title == "A field guide to lichens" && list.item("nope") == nil)
    }

    @Test func aPageIsInSafariUntilFoundGone() {
        #expect(Fixtures.item().inSafari)
        #expect(!Fixtures.item(removed: Fixtures.date).inSafari)
    }

    @Test func addressesAreKeptAsWritten() {
        #expect(Links.web("  https://example.com/a?b=c  ") == "https://example.com/a?b=c")
        #expect(Links.web(String(repeating: "a", count: 9000)) == nil)
        #expect(Links.web("https://example.com/" + String(repeating: "a", count: 9000)) == nil)
    }

    @Test func titlesFromAddresses() {
        #expect(SafariBookmarks.fallbackTitle("https://www.example.com/a/b/") == "example.com/a/b")
        #expect(SafariBookmarks.fallbackTitle("http://example.com") == "example.com")
    }

    @Test(arguments: [("ABC-123", true), ("", false), ("a.b", false), ("../x", false), ("é", false), (String(repeating: "a", count: 129), false)])
    func ids(_ value: String, _ kept: Bool) {
        #expect((SafariBookmarks.cleanID(value) != nil) == kept)
    }

    @Test func pagesSurviveTheRecord() throws {
        let item = Fixtures.item("R1", site: "Tide Watch", read: true, viewedDaysAgo: 1, removed: Fixtures.date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Item.self, from: encoder.encode(item)) == item)
    }
}
