# Changelog

## 0.1.0 (2026-11-10)

First release.

- **Save your Safari Reading List as a bookmarks file,** the HTML format every browser exports, which Linkding, Karakeep, Raindrop.io and browsers import. Unread pages are marked so Linkding keeps them unread.
- **Export to a folder you choose:** `Reading List.md`, with unread pages as open tasks and read ones checked off, `Reading List.html`, and `Reading List.csv` in Instapaper's layout for Wallabag and Readwise Reader. `Reading List.json` and a note for each page too, if you turn them on.
- **Every page's title, address, site, date added, preview text and read status.**
- **Only what's new on each run,** with a record in the export folder so nothing is duplicated, and pages stay in the export after you clear them from Safari.
- **Never overwrites your edits:** a file you've changed is left alone, and files already in the folder are never touched.
- **Automatic export,** off until you turn it on.
- **A window to search your Reading List** by any word in a page's title, site, address or preview, filtered to unread or read, with a button to copy each link.
- **The `reading-list-export` command line tool** to list pages, print the bookmarks file and export.
- **Open at login**, on by default and easy to turn off.
- Runs in the App Sandbox with no network access, read-only access to Safari's bookmarks file alone, and write access only to the folder or file you choose.
