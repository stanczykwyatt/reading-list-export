import AppKit
import ReadingListCore
import SwiftUI

/// The main window: every page in your Reading List, searchable by any word in its title, site,
/// address or preview, and filtered to unread or read.
struct ReadingView: View {
    @Bindable var model: ReadingModel
    var home = SafariBookmarks.realHome
    var now: () -> Date = Date.init
    var export: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var openPrivacySettings: () -> Void = {}
    /// Unread marks and the export button's tint. Your accent color in the app; a fixed blue in the screenshots.
    var tint = Color.accentColor
    var renderer = Renderer()

    @State var query = ""
    @State var filter: Search.Filter = .all
    /// The page whose link was just copied, to say so for a moment.
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch model.status {
            case .loading:
                ProgressView("Reading Safari…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .problem(let error):
                problem(error)
            case .ready:
                if model.list.items.isEmpty {
                    ContentUnavailableView {
                        Label("Your Reading List is empty", systemImage: "text.badge.plus")
                    } description: {
                        Text("Pages you add to your Reading List in Safari, on this Mac or synced from your iPhone and iPad through iCloud, show up here.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pages(Search.run(query, filter: filter, in: model.list.items))
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
        // The window draws this anyway; drawing it here too keeps off-screen renders right in dark mode.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status == .ready ? Describe.count(model.list.items.count, "page") + " saved" : "Reading List Export")
                    .font(.title2.weight(.semibold))
                if model.status == .ready && !model.list.items.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if model.status == .ready && !model.list.items.isEmpty {
                Picker("Show", selection: $filter) {
                    Text("All").tag(Search.Filter.all)
                    Text("Unread").tag(Search.Filter.unread)
                    Text("Read").tag(Search.Filter.read)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                search
            }
            if model.folder == nil {
                Button("Choose Export Folder…", action: chooseFolder)
                    .disabled(model.status != .ready)
            } else {
                Button(action: export) {
                    Text(model.isExporting ? "Exporting…" : model.pending > 0 ? "Export \(Describe.count(model.pending, "New Page"))" : "Export Now")
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(model.status != .ready || model.isExporting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        var parts = ["\(model.list.unread.count) unread", "\(model.list.read.count) read"]
        if let oldest = model.list.items.compactMap(\.added).min() {
            parts.append("saving since \(renderer.day(oldest))")
        }
        return parts.joined(separator: " · ")
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search titles, sites and text", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 230)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let problem = model.exportProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if let folder = model.folder {
                Label("Exporting to \(Describe.path(folder.url, home: home))", systemImage: "folder")
                if let last = model.lastExport {
                    Text("· last export \(Describe.relative(last.date, now: now()))")
                }
            } else {
                Label("Choose a folder, like one in your Obsidian vault, to export to.", systemImage: "folder.badge.plus")
            }
            Spacer()
            Text("Read-only: Safari is never changed.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func problem(_ error: LibraryError) -> some View {
        if error == .noPermission {
            ContentUnavailableView {
                Label("Turn on Full Disk Access", systemImage: "lock.shield")
            } description: {
                Text("macOS keeps Safari's data private. Turn on Reading List Export in System Settings → Privacy & Security → Full Disk Access, then come back here. The App Sandbox still limits it to reading Safari's bookmarks file, and writing to the folder you choose.")
            } actions: {
                Button("Open Privacy & Security Settings…", action: openPrivacySettings)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Can't read Safari's Reading List", systemImage: "exclamationmark.circle")
            } description: {
                Text(Describe.problem(error))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: The pages

    @ViewBuilder
    private func pages(_ shown: [Item]) -> some View {
        if shown.isEmpty {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView {
                    Label(filter == .read ? "Nothing read yet" : "All caught up", systemImage: filter == .read ? "circle.dashed" : "checkmark.circle")
                } description: {
                    Text(filter == .read ? "Pages you open from your Reading List count as read." : "Every page in your Reading List is read.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: query)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("\(Describe.count(shown.count, "page")) \(shown.count == 1 ? "matches" : "match") \"\(query)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                    ForEach(shown) { item in
                        row(item)
                        Divider().opacity(0.5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.read ? "checkmark.circle" : "circle.fill")
                .font(.system(size: item.read ? 12 : 8))
                .foregroundStyle(item.read ? Color.secondary : tint)
                .frame(width: 14)
                .help(item.read ? "Read" : "Unread")
            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(item.title, around: query, bold: !item.read))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(details(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let preview = item.preview {
                    Text(highlighted(preview, around: query, bold: false))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied == item.id ? "Copied" : "Copy Link") {
                model.copy([item])
                copied = item.id
            }
            .controlSize(.small)
            .help(item.url)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Link") { model.copy([item]) }
            Button("Copy as Markdown Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(renderer.link(item), forType: .string)
            }
        }
    }

    private func details(_ item: Item) -> String {
        var parts: [String] = []
        if !item.site.isEmpty { parts.append(item.site) }
        if let added = item.added { parts.append("added \(Describe.relative(added, now: now()))") }
        if item.read, let viewed = item.viewed { parts.append("read \(Describe.relative(viewed, now: now()))") }
        return parts.joined(separator: " · ")
    }

    /// The text with the searched words in bold and tinted.
    private func highlighted(_ text: String, around query: String, bold: Bool) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for range in Search.ranges(of: query, in: text) where range.lowerBound >= cursor {
            out += AttributedString(text[cursor..<range.lowerBound])
            var match = AttributedString(text[range])
            match.font = .body.bold()
            match.backgroundColor = Color.yellow.opacity(0.35)
            out += match
            cursor = range.upperBound
        }
        out += AttributedString(text[cursor...])
        if bold { out.font = .body.weight(.medium) }
        return out
    }
}

/// The window, made the first time it's opened and kept for next time.
@MainActor
final class ReadingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeView: () -> ReadingView
    /// Called when you close the window.
    var onClose: (() -> Void)?
    /// Called when the window comes to the front.
    var onActivate: (() -> Void)?

    init(makeView: @escaping () -> ReadingView) {
        self.makeView = makeView
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onActivate?()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
        window.title = "Reading List Export"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 860, height: 600))
        if !window.setFrameUsingName("ReadingWindow") {
            window.center()
        }
        window.setFrameAutosaveName("ReadingWindow")
        return window
    }
}
