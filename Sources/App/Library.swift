import Foundation

struct LibraryItem: Codable, Identifiable, Hashable {
    enum Source: Codable, Hashable {
        case file(bookmark: Data)       // security-scoped bookmark, never a path
        case youtube(watchURL: URL)     // stream URLs expire; re-extract every play
    }

    var id = UUID()
    var title: String
    var artist: String
    var source: Source
    var isVideo: Bool
}

/// ponytail: whole library is one Codable array in one JSON file. Personal library, fits in
/// memory; SwiftData when it doesn't.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []

    private var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("library.json")
    }

    init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([LibraryItem].self, from: data) {
            items = saved
        }
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: file, options: .atomic)
    }

    private static let videoExtensions: Set<String> =
        ["mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m3u8"]

    /// Import picked files. Stores bookmarks; "Artist - Title.ext" filenames split into fields.
    func add(pickedURLs: [URL]) {
        for url in pickedURLs {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let bookmark = try? url.bookmarkData(options: .minimalBookmark) else { continue }

            let base = url.deletingPathExtension().lastPathComponent
            let parts = base.components(separatedBy: " - ")
            let (artist, title) = parts.count >= 2
                ? (parts[0], parts.dropFirst().joined(separator: " - "))
                : ("", base)

            items.append(LibraryItem(
                title: title, artist: artist,
                source: .file(bookmark: bookmark),
                isVideo: Self.videoExtensions.contains(url.pathExtension.lowercased())))
        }
        save()
    }

    func add(youtubeURL: URL) {
        items.append(LibraryItem(title: youtubeURL.absoluteString, artist: "YouTube",
                                 source: .youtube(watchURL: youtubeURL), isVideo: true))
        save()
    }

    func update(_ item: LibraryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item; save() }
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    /// Resolve a file item's bookmark to a URL. Caller must start/stop security scope.
    func resolveURL(_ item: LibraryItem) -> URL? {
        guard case let .file(bookmark) = item.source else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            var fresh = item
            if let data = try? url.bookmarkData(options: .minimalBookmark) {
                fresh.source = .file(bookmark: data)
                update(fresh)
            }
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }
}
