// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadingListExport",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReadingListExport", targets: ["ReadingListExport"]),
        .executable(name: "reading-list-export", targets: ["ReadingListExportCLI"]),
    ],
    targets: [
        // Reading Safari's Reading List, and writing the Markdown, bookmarks file, CSV, JSON and
        // export record, with nothing tied to the app, so it can be tested against made-up
        // bookmarks files in throwaway folders.
        .target(name: "ReadingListCore"),
        .executableTarget(name: "ReadingListExport", dependencies: ["ReadingListCore"]),
        .executableTarget(name: "ReadingListExportCLI", dependencies: ["ReadingListCore"]),
        .testTarget(name: "ReadingListCoreTests", dependencies: ["ReadingListCore"]),
        // The app's glue, tested with a made-up Reading List and windows that are never shown.
        .testTarget(name: "ReadingListExportTests", dependencies: ["ReadingListExport", "ReadingListCore"]),
    ]
)
