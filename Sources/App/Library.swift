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

    /// Folder path components relative to the imported root, e.g. ["Rock", "Album1"]. Empty for
    /// loose items and YouTube adds. This is the whole filesystem-style library — folders are the
    /// organization, subfolders are the playlists.
    var folders: [String] = []

    /// YouTube items get a free thumbnail from the video id; local files show an icon.
    var thumbnailURL: URL? {
        guard case let .youtube(watchURL) = source else { return nil }
        let id = URLComponents(url: watchURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value
            ?? (watchURL.host?.contains("youtu.be") == true ? watchURL.lastPathComponent : nil)
        return id.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }
}

/// ponytail: whole library is one Codable array in one JSON file. Personal library, fits in
/// memory; SwiftData when it doesn't.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    /// User-created folders that may hold no items yet — the derived tree can't represent an
    /// empty folder, so these are persisted alongside the items.
    @Published private(set) var customFolders: [[String]] = []
    /// Bumped when background artwork extraction finishes, so rows re-render with covers.
    @Published private(set) var artworkVersion = 0

    private var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var file: URL { dir.appendingPathComponent("library.json") }
    private var foldersFile: URL { dir.appendingPathComponent("folders.json") }

    init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([LibraryItem].self, from: data) {
            items = saved
        }
        if let data = try? Data(contentsOf: foldersFile),
           let saved = try? JSONDecoder().decode([[String]].self, from: data) {
            customFolders = saved
        }
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: file, options: .atomic)
        try? JSONEncoder().encode(customFolders).write(to: foldersFile, options: .atomic)
    }

    // MARK: - Organizing

    /// Create an empty folder under `parent`. No-op if it already exists.
    func createFolder(named name: String, in parent: [String]) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let path = parent + [clean]
        if !customFolders.contains(path), children(of: parent).folders.firstIndex(of: clean) == nil {
            customFolders.append(path)
            save()
        }
    }

    /// Move an item into a different folder path.
    func move(_ item: LibraryItem, to path: [String]) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].folders = path
        save()
    }

    /// Every folder path in the library (derived from items + custom), for a move picker.
    func allFolders() -> [[String]] {
        var set = Set<[String]>()
        for item in items where !item.folders.isEmpty {
            for depth in 1...item.folders.count { set.insert(Array(item.folders.prefix(depth))) }
        }
        customFolders.forEach { set.insert($0) }
        return set.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
    }

    private static let videoExtensions: Set<String> =
        ["mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m3u8"]

    private static let mediaExtensions: Set<String> = videoExtensions.union(
        ["mp3", "aac", "m4a", "flac", "opus", "ogg", "wav", "aiff", "wma", "ape", "caf"])

    /// Import picked folders. Each folder's subtree is preserved: a file at
    /// `Music/Rock/Album/song.mp3` (picking `Music`) lands under folders ["Music","Rock","Album"].
    /// Sidecar .lrc files attach on the spot — the folder's security scope covers its children
    /// now but won't at play time, so lyrics must be captured during import.
    func add(pickedURLs: [URL]) {
        for root in pickedURLs {
            // Picker URLs are scoped; folders already in Documents (in-place) are not — don't
            // hard-fail on the latter. Ask the filesystem whether it's a directory rather than
            // trusting the URL's trailing slash, which the picker doesn't always set.
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            let isDir = (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { importFolder(root) }
        }
        save()
        Task { await backfillArtwork() }
    }

    /// Extract embedded cover art for any file item that hasn't got a cached thumbnail yet.
    /// Runs off the import path via the stored bookmark, so it doesn't need the picker's scope.
    private func backfillArtwork() async {
        for item in items {
            guard case .file = item.source, !Artwork.exists(for: item.id.uuidString),
                  let url = resolveURL(item) else { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            await Artwork.store(from: url, key: item.id.uuidString)
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        artworkVersion += 1
    }

    private func importFolder(_ root: URL) {
        let rootName = root.lastPathComponent
        // Everything under this root replaces a prior import of the same top folder.
        items.removeAll { $0.folders.first == rootName }

        let files = FileManager.default
            .enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        for url in files where Self.mediaExtensions.contains(url.pathExtension.lowercased()) {
            // Path from root's parent down to (but not including) the file = folder chain.
            let rel = relativeComponents(of: url, under: root)
            guard let item = importFile(url, folders: [rootName] + rel.dropLast()) else { continue }
            let sidecar = url.deletingPathExtension().appendingPathExtension("lrc")
            if let lrc = try? String(contentsOf: sidecar, encoding: .utf8) {
                LyricsResolver.attach(lrcText: lrc, cacheKey: item.id.uuidString)
            }
        }
    }

    /// Path components of `url` relative to `root` (includes the filename as the last element).
    private func relativeComponents(of url: URL, under root: URL) -> [String] {
        let rootParts = root.standardizedFileURL.pathComponents
        let urlParts = url.standardizedFileURL.pathComponents
        return Array(urlParts.dropFirst(rootParts.count))
    }

    @discardableResult
    private func importFile(_ url: URL, folders: [String]) -> LibraryItem? {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let parts = base.components(separatedBy: " - ")
        let (artist, title) = parts.count >= 2
            ? (parts[0], parts.dropFirst().joined(separator: " - "))
            : ("", base)

        let item = LibraryItem(
            title: title, artist: artist,
            source: .file(bookmark: bookmark),
            isVideo: Self.videoExtensions.contains(url.pathExtension.lowercased()),
            folders: folders)
        items.append(item)
        return item
    }

    // MARK: - Filesystem-style browsing

    /// What lives directly inside `path`: immediate subfolder names + items in that exact folder.
    func children(of path: [String]) -> (folders: [String], items: [LibraryItem]) {
        var subfolders = Set<String>()
        var here: [LibraryItem] = []
        for item in items {
            guard item.folders.starts(with: path) else { continue }
            if item.folders.count == path.count {
                here.append(item)
            } else {
                subfolders.insert(item.folders[path.count])   // next component down
            }
        }
        // Custom (possibly empty) folders show up too.
        for f in customFolders where f.starts(with: path) && f.count > path.count {
            subfolders.insert(f[path.count])
        }
        let ordered = subfolders.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (ordered, here.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    /// Every item at or below `path` — a whole subtree plays as one queue.
    func descendants(of path: [String]) -> [LibraryItem] {
        items.filter { $0.folders.starts(with: path) }
    }

    /// YouTube adds and anything imported without a folder.
    var loose: [LibraryItem] { items.filter(\.folders.isEmpty) }

    func add(youtubeURL: URL) {
        items.append(LibraryItem(title: youtubeURL.absoluteString, artist: "YouTube",
                                 source: .youtube(watchURL: youtubeURL), isVideo: true))
        save()
    }

    func update(_ item: LibraryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item; save() }
    }

    func remove(_ item: LibraryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Delete a whole folder subtree.
    func removeFolder(_ path: [String]) {
        items.removeAll { $0.folders.starts(with: path) }
        customFolders.removeAll { $0.starts(with: path) }
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
