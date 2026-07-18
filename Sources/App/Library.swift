import AVFoundation
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

    /// When it entered the library — powers "Date Added" sorting. Optional so libraries saved
    /// before this field decode cleanly (nil sorts oldest).
    var dateAdded: Date?

    /// Plays, counted at the moment playback is started. Powers Home's "most played" and, later,
    /// Wrapped. Defaulted so libraries saved before these fields decode cleanly.
    var playCount: Int = 0
    var lastPlayed: Date?

    /// Heart from the player's burger menu. Defaulted so older libraries decode cleanly.
    var liked: Bool = false

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
/// File-manager sort options, applied to the items within a folder. Folders always sort by name.
enum SortField: String, CaseIterable, Identifiable {
    case name = "Name", dateAdded = "Date Added", artist = "Artist", kind = "Kind"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .name: "textformat"
        case .dateAdded: "clock"
        case .artist: "music.mic"
        case .kind: "square.grid.2x2"
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    /// User-created folders that may hold no items yet — the derived tree can't represent an
    /// empty folder, so these are persisted alongside the items.
    @Published private(set) var customFolders: [[String]] = []
    /// Bumped when background artwork extraction finishes, so rows re-render with covers.
    @Published private(set) var artworkVersion = 0

    @Published var sortField: SortField = .name { didSet { persistSort() } }
    @Published var sortAscending = true { didSet { persistSort() } }

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
        if let raw = UserDefaults.standard.string(forKey: "sortField"),
           let f = SortField(rawValue: raw) { sortField = f }
        sortAscending = UserDefaults.standard.object(forKey: "sortAsc") as? Bool ?? true
    }

    private func persistSort() {
        UserDefaults.standard.set(sortField.rawValue, forKey: "sortField")
        UserDefaults.standard.set(sortAscending, forKey: "sortAsc")
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

    /// Batch move / delete for multi-select.
    func move(_ ids: Set<UUID>, to path: [String]) {
        for i in items.indices where ids.contains(items[i].id) { items[i].folders = path }
        save()
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    /// Rename a folder: rewrite the component at its depth for every item under it, and any
    /// custom-folder paths that pass through it.
    func renameFolder(_ path: [String], to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !path.isEmpty else { return }
        let depth = path.count - 1
        let rewrite: ([String]) -> [String] = { comps in
            guard comps.count >= path.count, Array(comps.prefix(path.count)) == path else { return comps }
            var c = comps; c[depth] = clean; return c
        }
        for i in items.indices { items[i].folders = rewrite(items[i].folders) }
        customFolders = customFolders.map(rewrite)
        save()
    }

    /// Move a whole folder subtree under a new parent (reparent items + custom folders).
    func moveFolder(_ path: [String], under newParent: [String]) {
        guard let name = path.last, !newParent.starts(with: path) else { return }  // no cycles
        let dest = newParent + [name]
        let reparent: ([String]) -> [String] = { comps in
            guard comps.starts(with: path) else { return comps }
            return dest + Array(comps.dropFirst(path.count))
        }
        for i in items.indices { items[i].folders = reparent(items[i].folders) }
        customFolders = customFolders.map(reparent)
        if !customFolders.contains(dest) { customFolders.append(dest) }
        save()
    }

    // MARK: - File info

    struct FileInfo {
        var location: String       // filename for files, watch URL for YouTube
        var kind: String
        var size: Int64?
        var duration: TimeInterval?
        var folder: String
        var added: Date?
    }

    /// Resolve on-disk details for the info panel. Async because size/duration need the file.
    func info(for item: LibraryItem) async -> FileInfo {
        let folder = item.folders.isEmpty ? "Library" : item.folders.joined(separator: " / ")
        guard case .file = item.source, let url = resolveURL(item) else {
            if case let .youtube(watch) = item.source {
                return FileInfo(location: watch.absoluteString, kind: "YouTube",
                                size: nil, duration: nil, folder: folder, added: item.dateAdded)
            }
            return FileInfo(location: item.title, kind: "—", size: nil, duration: nil,
                            folder: folder, added: item.dateAdded)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        let duration = try? await AVURLAsset(url: url).load(.duration).seconds
        return FileInfo(location: url.lastPathComponent,
                        kind: url.pathExtension.uppercased(),
                        size: size,
                        duration: duration.flatMap { $0.isFinite ? $0 : nil },
                        folder: folder, added: item.dateAdded)
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
            folders: folders, dateAdded: Date())
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
        return (ordered, sorted(here))
    }

    /// Apply the current sort to a set of items.
    func sorted(_ items: [LibraryItem]) -> [LibraryItem] {
        let by: (LibraryItem, LibraryItem) -> Bool
        switch sortField {
        case .name:
            by = { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            by = { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .dateAdded:
            by = { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
        case .kind:
            by = { !$0.isVideo && $1.isVideo }   // audio before video
        }
        let s = items.sorted(by: by)
        return sortAscending ? s : s.reversed()
    }

    /// Every item at or below `path` — a whole subtree plays as one queue.
    func descendants(of path: [String]) -> [LibraryItem] {
        items.filter { $0.folders.starts(with: path) }
    }

    /// YouTube adds and anything imported without a folder.
    var loose: [LibraryItem] { items.filter(\.folders.isEmpty) }

    func add(youtubeURL: URL) {
        items.append(LibraryItem(title: youtubeURL.absoluteString, artist: "YouTube",
                                 source: .youtube(watchURL: youtubeURL), isVideo: true,
                                 dateAdded: Date()))
        save()
    }

    func update(_ item: LibraryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item; save() }
    }

    /// Count a play. Silently ignores items that aren't in the library — remote playlist entries
    /// are synthesised per play and have ids that were never stored.
    func recordPlay(_ item: LibraryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].playCount += 1
        items[i].lastPlayed = Date()
        save()
    }

    /// Folders that directly hold tracks — this library's notion of an album — ranked by total
    /// plays. Parent folders are excluded so a play isn't counted twice up the tree.
    /// ponytail: rescans on every call; it's a personal library and Home renders on appear.
    func mostPlayedAlbums(limit: Int = 6) -> [(path: [String], plays: Int)] {
        allFolders()
            .map { ($0, children(of: $0).items.reduce(0) { $0 + $1.playCount }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (path: $0.0, plays: $0.1) }
    }

    func mostPlayedTracks(limit: Int = 6) -> [LibraryItem] {
        items.filter { $0.playCount > 0 }
            .sorted { $0.playCount > $1.playCount }
            .prefix(limit)
            .map { $0 }
    }

    /// Re-read a file's embedded tags (title / artist) and cover art, and update the item
    /// (inbox-2 "fetch metadata"). Embedded tags only — no online lookup.
    func fetchMetadata(_ item: LibraryItem) async {
        guard case .file = item.source, let url = resolveURL(item) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var updated = item
        let asset = AVURLAsset(url: url)
        if let meta = try? await asset.load(.commonMetadata) {
            let title = try? await AVMetadataItem.metadataItems(
                from: meta, filteredByIdentifier: .commonIdentifierTitle).first?.load(.stringValue)
            let artist = try? await AVMetadataItem.metadataItems(
                from: meta, filteredByIdentifier: .commonIdentifierArtist).first?.load(.stringValue)
            if let t = title ?? nil, !t.isEmpty { updated.title = t }
            if let a = artist ?? nil, !a.isEmpty { updated.artist = a }
        }
        await Artwork.store(from: url, key: item.id.uuidString)
        update(updated)
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
