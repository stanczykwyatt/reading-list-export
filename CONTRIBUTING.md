# Contributing

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Reporting a page it read wrong

If a page is missing, has the wrong title, date or read status, or a read-later app won't import one of the files, open a [bug report](https://github.com/stanczykwyatt/reading-list-export/issues/new?template=bug.yml) with your macOS and Safari versions and what you expected. Please don't attach your exported files or paste the pages in your Reading List: describe them instead, like "a page I saved on my iPhone" or "a page I marked unread again".

If Safari changes how it stores the Reading List in a new version, the output of this command helps the most. It lists only the names of the fields Safari keeps for each page, nothing you've saved:

```bash
plutil -convert json -o - ~/Library/Safari/Bookmarks.plist | python3 -c 'import json,sys; d=json.load(sys.stdin); r=[c for c in d["Children"] if c.get("Title")=="com.apple.ReadingList"]; i=(r[0].get("Children") or [{}])[0] if r else {}; print(sorted(i), sorted(i.get("ReadingList",{})), sorted(i.get("ReadingListNonSync",{})))'
```

It needs Full Disk Access for your terminal app.

## Getting started

You need macOS 14 or later and Swift 6 (Xcode 16 or the Command Line Tools).

```bash
swift test                # run the tests
scripts/build-app.sh      # build "Reading List Export.app" and reading-list-export into ./build
open "build/Reading List Export.app"
```

Reading the bookmarks file, the Markdown, bookmarks, CSV and JSON files, the export record, search, the command line tool and all the wording live in `Sources/ReadingListCore`, with tests in `Tests/ReadingListCoreTests`. Those tests write made-up bookmarks files in throwaway folders, shaped like Safari's own. Changes to what goes in a file belong in `Render.swift`; changes to what's kept between runs belong in `Exporter.swift`, with a test that describes what you saved and read.

The menu bar app, the menu and the window are in `Sources/ReadingListExport`, tested in `Tests/ReadingListExportTests` with a made-up Reading List and windows that are never shown. No test reads your Safari data, writes outside a throwaway folder or puts anything on screen.

To redraw the art: `swift scripts/make-icon.swift`, `swift scripts/make-art.swift`, and `SCREENSHOT_DIR=docs swift test --filter Window` for the screenshots.

## Ground rules

- **No network access, ever.** Pull requests that fetch pages, add a network entitlement or add third-party analytics won't be merged.
- **Read-only.** Reading List Export never changes, moves or deletes anything in Safari, and never deletes anything anywhere.
- **Your files win.** Never overwrite a file the exporter didn't write, or one you've changed.
- **Only the Reading List.** No history, open tabs, passwords or other bookmarks. CI checks the app reads nothing else in Safari's folder.
- **Least access.** No new entitlements or files without a very good reason. Tab Groups will need one more read-only file, and that's the next one planned.
- **No new dependencies** without a very good reason. The app has none today, which keeps it easy to audit.
- **Made-up pages only** in screenshots, art, tests and bug reports.
- Run `swift test` before opening a pull request, and add tests for changes to `ReadingListCore`.
- Keep commits small, with a short message saying what changed and why.

## Security issues

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).
