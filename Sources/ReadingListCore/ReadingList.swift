import Foundation

/// One page in your Reading List.
public struct Item: Codable, Equatable, Sendable, Identifiable {
    /// Safari's ID for it, or one made from its address when Safari gave none.
    public var id: String
    public var url: String
    public var title: String
    /// The site's own name for itself, when Safari fetched one.
    public var siteName: String?
    /// The first lines of the page, as Safari shows under the title.
    public var preview: String?
    public var added: Date?
    /// Whether Safari counts it as read: you opened it, or marked it read.
    public var read: Bool
    /// When you last opened it, if Safari kept the date.
    public var viewed: Date?
    /// When an export first found it gone from Safari. Nil while it's still in your Reading List.
    public var removed: Date?

    public init(
        id: String, url: String, title: String, siteName: String? = nil, preview: String? = nil,
        added: Date? = nil, read: Bool = false, viewed: Date? = nil, removed: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.siteName = siteName
        self.preview = preview
        self.added = added
        self.read = read
        self.viewed = viewed
        self.removed = removed
    }

    /// The site's name, or failing that its address without `www.`, like `example.com`.
    public var site: String {
        if let siteName { return siteName }
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var inSafari: Bool { removed == nil }
}

/// Everything in your Reading List, newest first.
public struct ReadingList: Equatable, Sendable {
    public var items: [Item]
    /// Entries that weren't web pages, like a `file:` or `javascript:` link, which are left out.
    public var skipped: Int

    public init(items: [Item] = [], skipped: Int = 0) {
        self.items = items.sorted(by: Self.newest)
        self.skipped = skipped
    }

    public var unread: [Item] { items.filter { !$0.read } }
    public var read: [Item] { items.filter(\.read) }

    public func item(_ id: String) -> Item? {
        items.first { $0.id == id }
    }

    /// Newest added first, then undated ones, then by ID so the order never wobbles.
    public static func newest(_ a: Item, _ b: Item) -> Bool {
        switch (a.added, b.added) {
        case let (x?, y?) where x != y: x > y
        case (.some, nil): true
        case (nil, .some): false
        default: a.id < b.id
        }
    }
}

/// Web addresses, checked before they go anywhere.
enum Links {
    /// Far longer than any real page's address.
    static let longest = 8192

    /// `value` if it's a plain web address: http or https, with a host, and nothing in it that
    /// could break out of a link or a line, or hide in it, like a zero-width space. Anything else,
    /// like `javascript:`, gives nil.
    static func web(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.utf8.count <= longest,
              !value.unicodeScalars.contains(where: {
                  $0.properties.isWhitespace || [.control, .format].contains($0.properties.generalCategory) || Renderer.isHidden($0)
              }),
              let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty
        else { return nil }
        return value
    }
}
