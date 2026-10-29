# Security

Reading List Export reads what you've saved to read, which says a lot about you. So it's built to do that with as little access as possible, and to change nothing.

## Reporting a vulnerability

Please report security problems privately through **Security → Report a vulnerability** on this repository, not in a public issue. You'll get a reply within a few days.

## What Reading List Export can access

| | |
|---|---|
| **Safari's bookmarks file, read-only** | `~/Library/Safari/Bookmarks.plist`, through one read-only sandbox exception for that file alone. It reads the Reading List from it and skips over your other bookmarks. macOS blocks it from writing there. |
| **Full Disk Access** | macOS protects Safari's folder, so reading the file needs Full Disk Access, which you turn on yourself. The sandbox still applies on top of it, so the app itself still reaches only that file and your export folder. See [the signature](#the-signature) for what that means until releases are signed with a Developer ID. |
| **The folder you choose** | Read and write, after you pick it in the standard macOS folder picker. It's remembered with a security-scoped bookmark, kept in the app's own sandbox container. |
| **The file you save** | When you choose Save as Bookmarks File…, the one file you name in the save dialog. |
| **Two small files in the export folder** | `.reading-list-export.json`, the record of what's been exported, and `.reading-list-export.lock`, an empty file that keeps two exports into the same folder from running at once. |
| **Its own settings** | Your export folder and options, stored in the app's sandbox container. |

## What it can't access

- **The internet.** The app runs in the App Sandbox without a network entitlement, so macOS blocks every connection. It never fetches a page, a preview or an icon. CI checks every build for this, and that the app never starts another program, which could send something out another way. The one page it ever opens is the Full Disk Access page in System Settings.
- **The rest of Safari.** Your history, open tabs, Tab Groups, passwords, saved form data and offline reading archives are in other files in Safari's folder, which the sandbox blocks. A sandboxed copy with the same exception was tested reading `Bookmarks.plist`, then `History.db`, `RecentlyClosedTabs.plist` and Safari's tabs database: the first worked and the rest were denied. CI checks the code never names Safari's other files.
- **The rest of your files.** Documents, downloads, desktop, photos and everything else are blocked by the sandbox, even with Full Disk Access on. The same sandboxed copy was denied writing into Documents.
- **Other apps.** It has no Apple Events entitlement and no Accessibility permission, so it can't read or control other apps, Safari included.
- **Changing or deleting anything.** Its access to Safari is read-only, and its code never deletes a file; CI checks for that. In the export folder, it never overwrites a file it didn't write, and only rewrites one it wrote if something in it changed and you haven't touched it since.

Check it yourself on any copy of the app:

```bash
codesign -d --entitlements - "/Applications/Reading List Export.app"
```

The only entitlements are `com.apple.security.app-sandbox`, the read-only bookmarks file, `com.apple.security.files.user-selected.read-write` for the folder or file you choose, and `com.apple.security.files.bookmarks.app-scope` to remember the folder.

## How it handles things

- **Safari's file is read in one go.** Safari saves its bookmarks by writing a new file and swapping it in, so a single read always gets a whole file, never one half written. Nothing is copied anywhere else, and nothing is left behind.
- **What's in the Reading List is treated as untrusted.** Titles and previews come from web pages, so: the command line tool strips control characters before printing them, so a title can't send your terminal an escape sequence. Links are kept only if they're plain `http` or `https` addresses with a host and no spaces, control characters or invisible marks like zero-width spaces; `javascript:`, `file:` and `data:` links are left out and counted. IDs are kept only if they're letters, digits and dashes. Titles have path separators and anything a file name or Obsidian link can't hold removed from file names, which can't start with a dot. In Markdown, front matter is quoted, formatting in titles is escaped, a preview can't start a list or a rule, and angle brackets and backslashes in addresses are encoded. In the bookmarks file, HTML's special characters are escaped and line breaks removed, so nothing can end a tag early. In the CSV file, a title that would start a spreadsheet formula, like `=`, `+`, `@` or a `-` that isn't just a minus before a number, gets a leading apostrophe. Dates far outside any real one are dropped, and titles and previews are cut to a sensible length.
- **The export record is treated as untrusted too.** It lives in a folder you might sync or share, so every path in it must be a plain file name, or a folder and a file name, inside the export folder, and every link in it must pass the same check as Safari's. A record that points anywhere else, or whose entries don't match their own IDs, is refused, and nothing is exported until it's fixed. Before anything is written, its folder is checked again to be inside the export folder and outside Safari's folder, after following links.
- **Records it can't read stop the export.** If the folder's `.reading-list-export.json` is damaged or from a newer version, it stops rather than starting over, which would lose pages only the record still holds.
- **A Reading List that's still syncing changes nothing at first.** If Safari lists no pages at all, or fewer than half of those still in it last time, as it can while iCloud is still syncing, the export adds what's there but marks nothing as removed from Safari, and the menu says so. If the list is still that short a day later, you really did clear those pages, and they're marked as removed. Pages iCloud gives new IDs are recognized by their addresses, so nothing is exported twice.
- **Cleared pages don't come back as a backlog.** Pages you've cleared from Safari stay in the export, but the bookmarks file tags them `removed-from-safari` instead of marking them to read, and the CSV puts them in Archive, so importing doesn't bring them back as unread.
- **Nothing is written inside Safari's folder.** The export folder, or the file you save, can't be in it. The command line tool checks against both the file it reads and your real Safari folder, so reading a backup can't write into the original.
- **The lock file is never opened through a link,** so a link planted in a shared export folder can't make the command line tool create a file somewhere else.
- **The command line tool isn't sandboxed,** since it runs as you in your terminal. It uses the same code as the app, so it reads only the bookmarks file and writes only into the folder you give it. CI checks that only the export code writes files.
- It has no dependencies. Every line that runs is in this repository. CI checks that too.

## The signature

Releases are signed ad hoc, not with a paid Apple Developer ID. macOS ties the Full Disk Access you grant to that exact build, so no other program can borrow it by claiming to be Reading List Export. The catch is that each update counts as a new app: after updating, turn Full Disk Access on again in System Settings → Privacy & Security → Full Disk Access. macOS may also ask whether the new version can use the old one's data; that's just its settings. A Developer ID signature, which would keep the permission across updates, is planned.
