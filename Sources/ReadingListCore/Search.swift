import Foundation

/// Finds pages in the Reading List by their words, which Safari's sidebar can only do by title.
public enum Search {
    public enum Filter: String, CaseIterable, Sendable {
        case all, unread, read
    }

    /// Pages whose title, site, address or preview holds every word of `query`, ignoring case and
    /// accents, newest first.
    public static func run(_ query: String, filter: Filter = .all, in items: [Item]) -> [Item] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            switch filter {
            case .all: break
            case .unread: if item.read { return false }
            case .read: if !item.read { return false }
            }
            guard !terms.isEmpty else { return true }
            let text = [item.title, item.site, item.url, item.preview ?? ""].joined(separator: "\n")
            return terms.allSatisfy { contains(text, $0) }
        }
        .sorted(by: ReadingList.newest)
    }

    static func contains(_ text: String, _ term: String) -> Bool {
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }

    /// Where each word of `query` appears in `text`, for highlighting.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in query.split(whereSeparator: \.isWhitespace) {
            var start = text.startIndex
            while start < text.endIndex, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: start..<text.endIndex) {
                found.append(range)
                start = range.upperBound
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }
}
