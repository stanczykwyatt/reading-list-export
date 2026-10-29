import Foundation

/// The `reading-list-export` command line tool: list your Reading List, print it as a bookmarks
/// file, or export it all to a folder. It does the same as the app, for scripts, cron jobs and
/// Shortcuts.
public enum Command: Equatable {
    case list(filter: Search.Filter, json: Bool, limit: Int?)
    case bookmarks
    case export(folder: String, options: ExportOptions)
    case help
    case version

    public static let toolVersion = "0.1.0"

    public static let usage = """
        reading-list-export \(toolVersion): export your Safari Reading List.

        Usage:
          reading-list-export list [--unread | --read] [--limit <n>]   Pages, newest first
          reading-list-export list --json                Every page as JSON
          reading-list-export bookmarks                  Print it as a bookmarks file (HTML)
          reading-list-export export <folder>            Export what's new into <folder>

        Export options:
          --no-markdown      Don't write Reading List.md
          --no-bookmarks     Don't write Reading List.html
          --no-csv           Don't write Reading List.csv (Instapaper's layout)
          --json             Also write Reading List.json
          --notes            Also write a note for each page, in Pages

          --bookmarks-file <file>  Read another copy of Safari's Bookmarks.plist, like a backup
          --help, --version

        Reading Safari needs Full Disk Access for your terminal app, in System Settings →
        Privacy & Security → Full Disk Access. Nothing in Safari is ever changed.
        """

    public enum ParseError: Error, Equatable {
        case message(String)
    }

    /// The command, and the bookmarks file if one was given.
    public static func parse(_ arguments: [String]) throws -> (Command, file: String?) {
        var rest: [String] = []
        var file: String?
        var limit: Int?
        var flags = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--bookmarks-file" || argument == "--limit" {
                guard index + 1 < arguments.count else { throw ParseError.message("\(argument) needs a value.") }
                let value = arguments[index + 1]
                if argument == "--bookmarks-file" {
                    file = value
                } else {
                    guard let number = Int(value), number > 0 else { throw ParseError.message("--limit needs a number above 0.") }
                    limit = number
                    flags.insert(argument)
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--") { flags.insert(argument) } else if argument == "-h" { flags.insert("--help") } else { rest.append(argument) }
            index += 1
        }
        if flags.contains("--help") { return (.help, file) }
        if flags.contains("--version") { return (.version, file) }
        guard let name = rest.first else { return (.help, file) }

        func allow(_ allowed: Set<String>) throws {
            if let unknown = flags.subtracting(allowed).sorted().first {
                throw ParseError.message("Unknown option \(unknown) for \(name). See reading-list-export --help.")
            }
        }
        switch name {
        case "list":
            try allow(["--json", "--limit", "--unread", "--read"])
            guard rest.count == 1 else { throw ParseError.message("list takes no arguments.") }
            guard !(flags.contains("--unread") && flags.contains("--read")) else { throw ParseError.message("Choose --unread or --read, not both.") }
            let filter: Search.Filter = flags.contains("--unread") ? .unread : flags.contains("--read") ? .read : .all
            return (.list(filter: filter, json: flags.contains("--json"), limit: limit), file)
        case "bookmarks":
            try allow([])
            guard rest.count == 1 else { throw ParseError.message("bookmarks takes no arguments. To save it, use reading-list-export bookmarks > \"Reading List.html\"") }
            return (.bookmarks, file)
        case "export":
            try allow(["--no-markdown", "--no-bookmarks", "--no-csv", "--json", "--notes"])
            guard rest.count == 2 else { throw ParseError.message("export needs one folder to export into.") }
            let options = ExportOptions(
                markdown: !flags.contains("--no-markdown"),
                bookmarks: !flags.contains("--no-bookmarks"),
                csv: !flags.contains("--no-csv"),
                json: flags.contains("--json"),
                notes: flags.contains("--notes")
            )
            return (.export(folder: rest[1], options: options), file)
        default:
            throw ParseError.message("Unknown command \(name). See reading-list-export --help.")
        }
    }

    /// Runs the tool. Returns the exit status: 0 on success, 1 when something failed, 2 for a mistake in the arguments.
    public static func run(
        _ arguments: [String], home: URL = SafariBookmarks.realHome, workingDirectory: URL,
        renderer: Renderer = Renderer(), now: Date = Date(),
        out rawOut: (String) -> Void, err rawErr: (String) -> Void
    ) -> Int32 {
        // Titles and previews come from web pages, so nothing in them reaches the terminal that it
        // would read as a command, like an escape sequence that sets the clipboard.
        func out(_ text: String) { rawOut(Renderer.visible(text)) }
        func err(_ text: String) { rawErr(Renderer.visible(text)) }
        let command: Command, filePath: String?
        do {
            (command, filePath) = try parse(arguments)
        } catch ParseError.message(let message) {
            err(message)
            return 2
        } catch {
            return 2
        }
        func resolve(_ path: String) -> URL {
            let expanded = path == "~" ? home.path : path.hasPrefix("~/") ? home.path + path.dropFirst(1) : path
            return URL(fileURLWithPath: expanded, relativeTo: workingDirectory).standardizedFileURL
        }
        let source = filePath.map { SafariBookmarks(file: resolve($0)) } ?? SafariBookmarks(home: home)

        switch command {
        case .help:
            out(usage)
            return 0
        case .version:
            out("reading-list-export \(toolVersion)")
            return 0
        default:
            break
        }

        let list: ReadingList
        do {
            list = try source.read()
        } catch let error as LibraryError {
            err(error == .noPermission
                ? "Your terminal needs Full Disk Access to read Safari's Reading List. Turn it on in System Settings → Privacy & Security → Full Disk Access, then open a new terminal window."
                : Describe.problem(error))
            return 1
        } catch {
            err(error.localizedDescription)
            return 1
        }

        switch command {
        case .list(let filter, let json, let limit):
            let items = Array(Search.run("", filter: filter, in: list.items).prefix(limit ?? .max))
            if json {
                out(String(renderer.json(items).dropLast()))
                return 0
            }
            if items.isEmpty {
                out(list.items.isEmpty ? "Your Reading List is empty." : "No \(filter == .read ? "read" : "unread") pages.")
                return 0
            }
            for item in items {
                let when = item.added.map(renderer.day) ?? "undated   "
                out("\(when)  \(item.read ? "read  " : "unread")  \(Renderer.visible(item.title).replacingOccurrences(of: "\n", with: " "))")
                out("            \(item.url)")
            }
            return 0

        case .bookmarks:
            // print adds the last line break back.
            out(String(renderer.bookmarks(list.items).dropLast()))
            if list.skipped > 0 { err("Left out \(Describe.skipped(list.skipped)).") }
            return 0

        case .export(let folder, var options):
            options.renderer = renderer
            let exporter = Exporter(destination: resolve(folder), options: options)
            do {
                // Never into Safari's folder, or the real one when reading a copy.
                let protected = source.protectedFolders + SafariBookmarks(home: home).protectedFolders
                let report = try exporter.export(list, protected: protected, now: now)
                out(Describe.summary(report) + ".")
                for path in report.written { out("  + \(path)") }
                for path in report.kept { out("  = \(path): you've edited it, so it was left as it is") }
                if report.heldBack {
                    out("  = Safari lists far fewer pages than last time, as it can while iCloud is syncing, so none were marked as removed.")
                }
                if report.skipped > 0 { out("  … Left out \(Describe.skipped(report.skipped)).") }
                for failure in report.failed { err("  ! \(failure.file): \(failure.reason)") }
                return report.failed.isEmpty ? 0 : 1
            } catch let error as ExportError {
                err(Describe.problem(error))
                return 1
            } catch {
                err(error.localizedDescription)
                return 1
            }

        case .help, .version:
            return 0
        }
    }
}
