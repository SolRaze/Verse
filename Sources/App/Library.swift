import AVFoundation
import Foundation
import UIKit

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

    /// Embedded album tag, read on import (auto metadata). Empty when the file carried none;
    /// the Albums collection then falls back to the containing folder name. Defaulted so older
    /// libraries decode cleanly.
    var album: String = ""

    /// How this track groups under Albums: its album tag, else the folder it sits in. Empty
    /// only for a loose, tagless file.
    var albumKey: String { album.isEmpty ? (folders.last ?? "") : album }

    /// Position within the album, filled by the online album lookup (disc-aware). Optional so
    /// older libraries decode cleanly; nil sorts after numbered tracks, then by title.
    var trackNumber: Int?
    var discNumber: Int?

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

/// Tags saved as `<file>.verse.json` beside the track (inbox-3 in-place metadata): the user's
/// edits live with the files, and a re-import reads them back instead of re-parsing filenames.
struct SidecarTags: Codable {
    var title: String
    var artist: String
    var liked: Bool?
    // Full per-track state rides the sidecar (all optional — older sidecars decode fine).
    // This is the rebuild insurance: app data wiped → re-import the folder → tags, album,
    // likes AND play history restore from beside the files. No copy into app storage needed.
    var album: String?
    var playCount: Int?
    var lastPlayed: Date?
    var trackNumber: Int?
    var discNumber: Int?

    static func url(besides mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension()
            .appendingPathExtension("verse").appendingPathExtension("json")
    }
}

/// User-made playlist (distinct from scraped RemotePlaylists): ordered item ids, persisted
/// with the library. Tracks are references — deleting a library item just drops dead ids on
/// read.
struct LocalPlaylist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var itemIDs: [UUID] = []
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

    /// Imported root-folder name → security-scoped bookmark of that folder. A file's own
    /// bookmark never covers its siblings, so writing sidecars beside a track needs the root's
    /// scope. Captured at import; folders imported before this existed need one re-import.
    private var rootBookmarks: [String: Data] = [:]

    private var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var file: URL { dir.appendingPathComponent("library.json") }
    private var foldersFile: URL { dir.appendingPathComponent("folders.json") }
    private var rootsFile: URL { dir.appendingPathComponent("roots.json") }
    private var localPlaylistsFile: URL { dir.appendingPathComponent("playlists-local.json") }
    @Published private(set) var localPlaylists: [LocalPlaylist] = []

    init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([LibraryItem].self, from: data) {
            items = saved
        }
        if let data = try? Data(contentsOf: foldersFile),
           let saved = try? JSONDecoder().decode([[String]].self, from: data) {
            customFolders = saved
        }
        if let data = try? Data(contentsOf: rootsFile),
           let saved = try? JSONDecoder().decode([String: Data].self, from: data) {
            rootBookmarks = saved
        }
        if let data = try? Data(contentsOf: localPlaylistsFile),
           let saved = try? JSONDecoder().decode([LocalPlaylist].self, from: data) {
            localPlaylists = saved
        }
        if let raw = UserDefaults.standard.string(forKey: "sortField"),
           let f = SortField(rawValue: raw) { sortField = f }
        sortAscending = UserDefaults.standard.object(forKey: "sortAsc") as? Bool ?? true
        if let bm = try? Data(contentsOf: dir.appendingPathComponent("sidecar-dir.bookmark")) {
            var stale = false
            customSidecarFolderName = (try? URL(resolvingBookmarkData: bm,
                                                bookmarkDataIsStale: &stale))?.lastPathComponent
        }
    }

    private func persistSort() {
        UserDefaults.standard.set(sortField.rawValue, forKey: "sortField")
        UserDefaults.standard.set(sortAscending, forKey: "sortAsc")
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: file, options: .atomic)
        try? JSONEncoder().encode(customFolders).write(to: foldersFile, options: .atomic)
        try? JSONEncoder().encode(rootBookmarks).write(to: rootsFile, options: .atomic)
        try? JSONEncoder().encode(localPlaylists).write(to: localPlaylistsFile, options: .atomic)
    }

    // MARK: - Local playlists

    func newPlaylist(with item: LibraryItem? = nil) {
        var pl = LocalPlaylist(name: "Playlist \(localPlaylists.count + 1)")
        if let item { pl.itemIDs = [item.id] }
        localPlaylists.append(pl)
        save()
    }

    func add(_ item: LibraryItem, to playlist: LocalPlaylist) {
        guard let i = localPlaylists.firstIndex(where: { $0.id == playlist.id }),
              !localPlaylists[i].itemIDs.contains(item.id) else { return }
        localPlaylists[i].itemIDs.append(item.id)
        save()
    }

    func remove(_ item: LibraryItem, from playlist: LocalPlaylist) {
        guard let i = localPlaylists.firstIndex(where: { $0.id == playlist.id }) else { return }
        localPlaylists[i].itemIDs.removeAll { $0 == item.id }
        save()
    }

    func renamePlaylist(_ playlist: LocalPlaylist, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty,
              let i = localPlaylists.firstIndex(where: { $0.id == playlist.id }) else { return }
        localPlaylists[i].name = clean
        save()
    }

    func removePlaylist(_ playlist: LocalPlaylist) {
        localPlaylists.removeAll { $0.id == playlist.id }
        save()
    }

    /// Resolve a playlist's ids to items, keeping order and skipping deleted tracks.
    func tracks(of playlist: LocalPlaylist) -> [LibraryItem] {
        playlist.itemIDs.compactMap { id in items.first { $0.id == id } }
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
            if isDir {
                // Keep write access to the tree — sidecar tags/lyrics land beside the files.
                if let bm = try? root.bookmarkData(options: .minimalBookmark) {
                    rootBookmarks[root.lastPathComponent] = bm
                }
                importFolder(root)
            }
        }
        save()
        Task { await backfillMetadata(); await backfillArtwork(); await onlinePass() }
    }

    /// Import individual picked files as LOOSE items (folders: []). Unlike folder import this
    /// stores NO root-folder bookmark — each file keeps only its own minimal bookmark, which
    /// covers the file but not its directory. That's the point: import files, never associate
    /// the whole folder. Sibling .lrc / .verse.json are read while the picker scope is held,
    /// since a file's own scope won't reach them later.
    func add(pickedFiles urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard Self.mediaExtensions.contains(url.pathExtension.lowercased()),
                  let item = importFile(url, folders: []) else { continue }
            let sidecar = url.deletingPathExtension().appendingPathExtension("lrc")
            if let lrc = try? String(contentsOf: sidecar, encoding: .utf8) {
                LyricsResolver.attach(lrcText: lrc, cacheKey: item.id.uuidString)
            }
        }
        save()
        Task { await backfillMetadata(); await backfillArtwork(); await onlinePass() }
    }

    /// Auto metadata on import: read embedded title/artist/album tags and associate each track
    /// with its artist and album. Only fills what import left blank — a sidecar or a real
    /// filename parse (`Artist - Title`) already wins, and user edits are never touched.
    /// ponytail: opens the asset a second time (backfillArtwork opens it too); personal library,
    /// not worth threading one asset through both passes.
    private func backfillMetadata() async {
        for item in items {
            guard case .file = item.source,
                  item.artist.isEmpty || item.album.isEmpty,   // nothing to do if both known
                  let url = resolveURL(item) else { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            let meta = try? await AVURLAsset(url: url).load(.commonMetadata)
            if scoped { url.stopAccessingSecurityScopedResource() }
            guard let meta else { continue }

            func tag(_ id: AVMetadataIdentifier) async -> String? {
                try? await AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: id)
                    .first?.load(.stringValue)
            }
            let title = await tag(.commonIdentifierTitle)
            let artist = await tag(.commonIdentifierArtist)
            let album = await tag(.commonIdentifierAlbumName)

            // Re-find by id: an await could have let another import mutate `items`.
            guard let i = items.firstIndex(where: { $0.id == item.id }) else { continue }
            let before = items[i]
            if items[i].artist.isEmpty, let a = artist, !a.isEmpty { items[i].artist = a }
            if items[i].album.isEmpty, let a = album, !a.isEmpty { items[i].album = a }
            // Title only when the filename parse gave nothing better (artist was empty too).
            if item.artist.isEmpty, let t = title, !t.isEmpty { items[i].title = t }
            // Filled something → persist it beside the file so a rebuild re-learns it free.
            if items[i] != before { writeTagsSidecar(items[i]) }
        }
        save()
    }

    /// Online enrichment: MusicBrainz album fill + Cover Art Archive hi-res cover (opt-in via
    /// Settings › Metadata), then LRCLIB lyrics into the cache and the `.lrc` sidecar (same
    /// no-toggle behaviour as play-time lyric lookup; the negative cache makes repeats free).
    /// Serial on purpose — free community services, ~1 req/s politeness lives in the clients.
    /// ponytail: whole-library loop with no resume; fine for a personal library.
    private func onlinePass() async {
        await onlineMetadataPass(force: false)
        await lyricsPass(force: false)
    }

    enum OnlineMode { case both, tags, art }

    /// Root folders the user excluded from online lookups (Settings › Metadata).
    static func excludedFolders() -> Set<String> {
        Set((UserDefaults.standard.string(forKey: Pref.metadataExcludedFolders) ?? "")
            .split(separator: "\n").map(String.init))
    }

    /// Online enrichment, grouped by album (2026-07-21): a multi-track album gets ONE release
    /// lookup — tracklist (disc/track numbers) + one hi-res cover shared across the folder —
    /// instead of a per-song recording search. Genuine singles (a one-track group) still go
    /// through the recording search. `force` = a Fetch button tap (bypasses the toggle, clears
    /// negative art markers); `mode` narrows to tags or art so a failure is attributable.
    private func onlineMetadataPass(force: Bool, mode: OnlineMode = .both) async {
        guard force || UserDefaults.standard.bool(forKey: Pref.onlineMetadata) else { return }
        let wantTags = mode != .art, wantArt = mode != .tags
        let label = mode == .tags ? "Metadata" : mode == .art ? "Artwork" : "Covers & metadata"
        let excluded = Self.excludedFolders()
        let eligible = items.filter {
            guard case .file = $0.source else { return false }
            if let root = $0.folders.first, excluded.contains(root) { return false }
            return true
        }
        let groups = Dictionary(grouping: eligible, by: \.albumKey)
        var hits = 0, misses = 0, skipped = 0
        for (albumName, groupItems) in groups {
            if groupItems.count >= 2, !albumName.isEmpty {
                rescanStatus = "Album · \(albumName)"
                let artist = Self.commonArtist(groupItems)
                guard let cand = await MetadataScraper.albumCandidates(
                          album: albumName, artist: artist).first else {
                    misses += groupItems.count; continue
                }
                let detail = await MetadataScraper.albumDetail(mbid: cand.releaseMBID, wantCover: wantArt)
                // Auto pass only trusts a release whose tracklist length matches the folder —
                // a mismatched count means the wrong pressing (deluxe/single/comp), and stamping
                // its numbers/album/cover would silently mistag. A Fetch-button/finder tap is
                // explicit intent, so `force` applies regardless (the finder lets the user pick).
                guard force || detail.tracks.count == groupItems.count else {
                    misses += groupItems.count; continue
                }
                applyAlbum(candidate: cand, tracks: detail.tracks, cover: detail.cover,
                           to: groupItems, wantTags: wantTags, wantArt: wantArt, force: force)
                hits += groupItems.count
            } else {
                for item in groupItems {
                    switch await fetchSingle(item, wantTags: wantTags, wantArt: wantArt,
                                             force: force, label: label) {
                    case .hit: hits += 1
                    case .miss: misses += 1
                    case .skip: skipped += 1
                    }
                }
            }
        }
        lastFetchSummary = "\(label): \(hits) found, \(misses) not matched"
            + (skipped > 0 ? ", \(skipped) already had it" : "")
            + (hits + misses == 0 ? " — nothing needed a lookup" : "")
    }

    private enum FetchOutcome { case hit, miss, skip }

    /// Single-track (or tagless-folder) lookup via MusicBrainz recording search — the pre-album
    /// path, kept for genuine singles.
    private func fetchSingle(_ item: LibraryItem, wantTags: Bool, wantArt: Bool,
                             force: Bool, label: String) async -> FetchOutcome {
        guard let url = resolveURL(item) else { return .skip }
        var current = items.first { $0.id == item.id } ?? item
        rescanStatus = "\(label) · \(current.title)"
        if force, wantArt, Artwork.image(for: item.id.uuidString) == nil {
            Artwork.invalidate(key: item.id.uuidString)
        }
        let needTags = wantTags && current.album.isEmpty
        let needArt = wantArt && (force || Artwork.image(for: item.id.uuidString) == nil)
        guard needTags || needArt else { return .skip }
        guard let found = await MetadataScraper.lookup(
                  title: current.title, artist: current.artist,
                  filename: url.deletingPathExtension().lastPathComponent) else { return .miss }
        if wantTags {
            if current.artist.isEmpty, !found.artist.isEmpty { current.artist = found.artist }
            if current.album.isEmpty, let a = found.album, !a.isEmpty { current.album = a }
        }
        if needArt, let cover = found.coverImage {
            Artwork.invalidate(key: item.id.uuidString)
            Artwork.store(image: cover, key: item.id.uuidString)
            artworkVersion += 1
        }
        update(current)
        return .hit
    }

    /// Most common non-empty artist in a group, the album's likely album-artist.
    private static func commonArtist(_ items: [LibraryItem]) -> String {
        Dictionary(grouping: items.map(\.artist).filter { !$0.isEmpty }, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key ?? ""
    }

    /// Fold a found release onto a folder of files: album name, per-track disc/track numbers
    /// (matched by title, else positional when counts line up), and one shared cover.
    private func applyAlbum(candidate: MetadataScraper.AlbumCandidate,
                            tracks: [MetadataScraper.TrackInfo], cover: UIImage?,
                            to groupItems: [LibraryItem],
                            wantTags: Bool, wantArt: Bool, force: Bool) {
        let files = groupItems.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let mbTracks = tracks.sorted { ($0.disc, $0.track) < ($1.disc, $1.track) }
        let matches = MetadataScraper.matchTracklist(fileTitles: files.map(\.title), tracks: mbTracks)
        for (i, item) in files.enumerated() {
            var current = items.first { $0.id == item.id } ?? item
            if wantTags {
                if !candidate.album.isEmpty { current.album = candidate.album }
                if current.artist.isEmpty, !candidate.artist.isEmpty { current.artist = candidate.artist }
                if let m = matches[i] { current.trackNumber = m.track; current.discNumber = m.disc }
            }
            let needArt = wantArt && (force || Artwork.image(for: item.id.uuidString) == nil)
            if needArt, let cover {
                Artwork.invalidate(key: item.id.uuidString)
                Artwork.store(image: cover, key: item.id.uuidString)
                artworkVersion += 1
            }
            update(current)
        }
    }

    /// Settings finder: apply a user-chosen release to every track of an album folder.
    func applyAlbumCandidate(_ cand: MetadataScraper.AlbumCandidate, to albumName: String) async {
        guard !rescanning else { return }
        rescanning = true
        defer { rescanning = false; rescanStatus = "" }
        rescanStatus = "Album · \(cand.album)"
        let groupItems = items.filter { $0.albumKey == albumName }
        let detail = await MetadataScraper.albumDetail(mbid: cand.releaseMBID)
        applyAlbum(candidate: cand, tracks: detail.tracks, cover: detail.cover,
                   to: groupItems, wantTags: true, wantArt: true, force: true)
    }

    /// Find Artwork: stamp a user-chosen cover on every track of an album folder.
    func applyAlbumArtwork(_ image: UIImage, to albumName: String) async {
        for item in items where item.albumKey == albumName {
            Artwork.invalidate(key: item.id.uuidString)
            Artwork.store(image: image, key: item.id.uuidString)
        }
        artworkVersion += 1
    }

    /// Settings finder: candidates for an album folder, seeded from its current tags.
    func albumCandidates(for albumName: String) async -> [MetadataScraper.AlbumCandidate] {
        let groupItems = items.filter { $0.albumKey == albumName }
        return await MetadataScraper.albumCandidates(
            album: albumName, artist: Self.commonArtist(groupItems))
    }

    /// LRCLIB lyrics into the cache + `.lrc` sidecars. `force` clears negative markers first
    /// so "nothing found" tracks retry.
    private func lyricsPass(force: Bool) async {
        let total = items.count
        for (n, item) in items.enumerated() {
            guard case .file = item.source, let url = resolveURL(item) else { continue }
            rescanStatus = "Lyrics \(n + 1)/\(total) · \(item.title)"
            if force { LyricsResolver.invalidateNegative(cacheKey: item.id.uuidString) }
            let scoped = url.startAccessingSecurityScopedResource()
            _ = await LyricsResolver.resolve(mediaURL: url, title: item.title,
                                             artist: item.artist, duration: nil,
                                             cacheKey: item.id.uuidString)
            if scoped { url.stopAccessingSecurityScopedResource() }
            exportLyricsSidecar(item)
        }
    }

    @Published private(set) var rescanning = false
    /// Live progress line for Settings ("Covers 3/40 · Track"), "" when idle.
    @Published private(set) var rescanStatus = ""
    /// Sticks around after a run so "did it do anything?" has an answer.
    @Published private(set) var lastFetchSummary = ""

    /// Settings "Rescan Library": embedded tags → embedded art → online metadata + hi-res
    /// covers (opt-in) → LRCLIB lyrics. Everything persists to the sidecars as it lands.
    func rescanLibrary() async {
        guard !rescanning else { return }
        rescanning = true
        defer { rescanning = false; rescanStatus = "" }
        rescanStatus = "Reading embedded tags…"
        await backfillMetadata()
        rescanStatus = "Extracting embedded covers…"
        await backfillArtwork()
        await onlinePass()
    }

    /// Settings "Fetch Metadata": explicit tap = consent, toggle bypassed. Tags only.
    func fetchOnlineTags() async {
        guard !rescanning else { return }
        rescanning = true
        defer { rescanning = false; rescanStatus = "" }
        await onlineMetadataPass(force: true, mode: .tags)
    }

    /// Settings "Fetch Artwork": hi-res covers only — separated so failures are attributable.
    func fetchOnlineArtwork() async {
        guard !rescanning else { return }
        rescanning = true
        defer { rescanning = false; rescanStatus = "" }
        await onlineMetadataPass(force: true, mode: .art)
    }

    /// Settings "Fetch Lyrics": LRCLIB for every track, negative markers cleared.
    func fetchAllLyrics() async {
        guard !rescanning else { return }
        rescanning = true
        defer { rescanning = false; rescanStatus = "" }
        await lyricsPass(force: true)
    }

    /// Hold-menu "Fetch Lyrics": one track, negative marker cleared so it genuinely retries.
    func fetchLyrics(_ item: LibraryItem) async {
        guard case .file = item.source, let url = resolveURL(item) else { return }
        LyricsResolver.invalidateNegative(cacheKey: item.id.uuidString)
        let scoped = url.startAccessingSecurityScopedResource()
        _ = await LyricsResolver.resolve(mediaURL: url, title: item.title, artist: item.artist,
                                         duration: nil, cacheKey: item.id.uuidString)
        if scoped { url.stopAccessingSecurityScopedResource() }
        exportLyricsSidecar(item)
    }

    /// Share payload: the media file plus freshly written tag + lyric files — the receiver
    /// gets everything the app knows about the track.
    /// ponytail: three files through the share sheet, not tags muxed into the audio —
    /// AVFoundation can't rewrite tags for arbitrary containers.
    func shareItems(_ item: LibraryItem) -> [URL]? {
        guard let media = resolveURL(item) else { return nil }
        var urls = [media]
        let tmp = FileManager.default.temporaryDirectory
        let base = media.deletingPathExtension().lastPathComponent
        let tags = SidecarTags(title: item.title, artist: item.artist, liked: item.liked,
                               album: item.album.isEmpty ? nil : item.album,
                               playCount: item.playCount > 0 ? item.playCount : nil,
                               lastPlayed: item.lastPlayed,
                               trackNumber: item.trackNumber, discNumber: item.discNumber)
        let tagURL = tmp.appendingPathComponent(base + ".verse.json")
        if let data = try? JSONEncoder().encode(tags), (try? data.write(to: tagURL)) != nil {
            urls.append(tagURL)
        }
        if let raw = LyricsResolver.cachedRaw(for: item.id.uuidString), !raw.isEmpty {
            let lrcURL = tmp.appendingPathComponent(base + ".lrc")
            if (try? raw.write(to: lrcURL, atomically: true, encoding: .utf8)) != nil {
                urls.append(lrcURL)
            }
        }
        return urls
    }

    // MARK: - Sidecar location (Settings › Metadata Location)

    private var sidecarDirFile: URL { dir.appendingPathComponent("sidecar-dir.bookmark") }
    /// Display name of the user-picked sidecar folder, nil = beside the music files.
    @Published private(set) var customSidecarFolderName: String?

    /// nil resets to "beside the files".
    func setCustomSidecarFolder(_ url: URL?) {
        guard let url else {
            try? FileManager.default.removeItem(at: sidecarDirFile)
            customSidecarFolderName = nil
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        if let bm = try? url.bookmarkData(options: .minimalBookmark) {
            try? bm.write(to: sidecarDirFile)
            customSidecarFolderName = url.lastPathComponent
        }
        if scoped { url.stopAccessingSecurityScopedResource() }
    }

    /// Resolve the custom sidecar dir with scope started; caller releases. nil = beside files.
    private func customSidecarDir() -> (url: URL, release: () -> Void)? {
        guard let bm = try? Data(contentsOf: sidecarDirFile) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bm, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        return (url, { url.stopAccessingSecurityScopedResource() })
    }

    /// Where a sidecar for `media` lives: user-picked folder (flat, filename-keyed) or beside
    /// the file. Returns the base URL (no extension) + a scope release.
    private func sidecarBase(for media: URL) -> (base: URL, release: () -> Void)? {
        if let (dir, release) = customSidecarDir() {
            return (dir.appendingPathComponent(media.deletingPathExtension().lastPathComponent),
                    release)
        }
        return nil  // caller falls back to beside-the-file with its own scope
    }

    /// One-file library backup (items + folders + playlists) for the share sheet — covers
    /// YouTube entries, which have no media files to carry sidecars.
    struct Backup: Codable {
        var items: [LibraryItem]
        var customFolders: [[String]]
        var localPlaylists: [LocalPlaylist]
    }

    func backupURL() -> URL? {
        let backup = Backup(items: items, customFolders: customFolders,
                            localPlaylists: localPlaylists)
        guard let data = try? JSONEncoder().encode(backup) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verse-backup.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Settings: remove one imported root — its items, hidden folder subtree, and bookmark.
    /// Sidecars beside the files stay, so re-importing later restores everything.
    func removeImportedRoot(_ name: String) {
        removeFolder([name])
        rootBookmarks.removeValue(forKey: name)
        save()
    }

    /// Imported root-folder names, shown in Settings › Library.
    var importedRoots: [String] { rootBookmarks.keys.sorted() }

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
        // Everything under this root replaces a prior import of the same top folder — but a
        // re-import is not destructive (inbox-3): files matched by folder path + filename keep
        // their identity, so play counts, likes, and the id-keyed lyric/artwork caches survive.
        var previous: [String: LibraryItem] = [:]
        for item in items where item.folders.first == rootName {
            guard case .file = item.source, let url = resolveURL(item) else { continue }
            previous[(item.folders + [url.lastPathComponent]).joined(separator: "/")] = item
        }
        items.removeAll { $0.folders.first == rootName }

        let files = FileManager.default
            .enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        for url in files where Self.mediaExtensions.contains(url.pathExtension.lowercased()) {
            // Path from root's parent down to (but not including) the file = folder chain.
            let rel = relativeComponents(of: url, under: root)
            guard let item = importFile(url, folders: [rootName] + rel.dropLast(),
                                        previous: previous) else { continue }
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
    private func importFile(_ url: URL, folders: [String],
                            previous: [String: LibraryItem] = [:]) -> LibraryItem? {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let parts = base.components(separatedBy: " - ")
        let (artist, title) = parts.count >= 2
            ? (parts[0], parts.dropFirst().joined(separator: " - "))
            : ("", base)

        var item = LibraryItem(
            title: title, artist: artist,
            source: .file(bookmark: bookmark),
            isVideo: Self.videoExtensions.contains(url.pathExtension.lowercased()),
            folders: folders, dateAdded: Date())

        // Same file as before (re-import): keep its identity and history; in-app edits beat
        // the filename re-parse.
        if let old = previous[(folders + [url.lastPathComponent]).joined(separator: "/")] {
            item.id = old.id
            item.dateAdded = old.dateAdded
            item.playCount = old.playCount
            item.lastPlayed = old.lastPlayed
            item.liked = old.liked
            item.title = old.title
            item.artist = old.artist
        }

        // Sidecar tags beat everything — they're the on-disk source of truth. Beside the
        // file first, then the user-picked sidecar folder (Settings › Metadata Location).
        var sidecarData = try? Data(contentsOf: SidecarTags.url(besides: url))
        if sidecarData == nil, let (base, release) = sidecarBase(for: url) {
            sidecarData = try? Data(contentsOf:
                base.appendingPathExtension("verse").appendingPathExtension("json"))
            release()
        }
        if let data = sidecarData,
           let tags = try? JSONDecoder().decode(SidecarTags.self, from: data) {
            item.title = tags.title
            item.artist = tags.artist
            if let liked = tags.liked { item.liked = liked }
            if let album = tags.album { item.album = album }
            // No in-app history for this file (fresh install / wiped data): adopt the
            // sidecar's play history — the rebuild-restore path.
            if item.playCount == 0, let plays = tags.playCount {
                item.playCount = plays
                item.lastPlayed = tags.lastPlayed
            }
            if let t = tags.trackNumber { item.trackNumber = t }
            if let d = tags.discNumber { item.discNumber = d }
        }

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
            // localizedStandardCompare = Finder-style numeric ordering, so "2 - x" precedes
            // "10 - x" — track lists play sequentially.
            by = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let old = items[i]
        items[i] = item
        save()
        // In-place metadata (inbox-3): user-visible edits land beside the file too. Bookmark
        // refreshes route through here as well — don't touch the disk for those.
        if old.title != item.title || old.artist != item.artist || old.liked != item.liked
            || old.album != item.album {
            writeTagsSidecar(item)
        }
    }

    // MARK: - Sidecars (inbox-3 in-place metadata)

    /// Start write scope on the imported root that holds `item`, and hand back the resolved
    /// media URL. Falls back to the file's own scope (tag reads work; sibling writes may not —
    /// pre-sidecar imports have no root bookmark until re-imported once).
    private func sidecarScope(for item: LibraryItem) -> (media: URL, release: () -> Void)? {
        guard case .file = item.source, let media = resolveURL(item) else { return nil }
        if let name = item.folders.first, let bm = rootBookmarks[name] {
            var stale = false
            if let root = try? URL(resolvingBookmarkData: bm, bookmarkDataIsStale: &stale),
               root.startAccessingSecurityScopedResource() {
                return (media, { root.stopAccessingSecurityScopedResource() })
            }
        }
        let scoped = media.startAccessingSecurityScopedResource()
        return (media, { if scoped { media.stopAccessingSecurityScopedResource() } })
    }

    // ponytail: file-imported loose items (add(pickedFiles:)) hold only the file's own bookmark,
    // which grants no directory scope — the atomic sidecar write here typically no-ops (try?), and
    // their metadata stays in-app (library.json). Upgrade path: fall back to folder import.
    private func writeTagsSidecar(_ item: LibraryItem) {
        let tags = SidecarTags(title: item.title, artist: item.artist, liked: item.liked,
                               album: item.album.isEmpty ? nil : item.album,
                               playCount: item.playCount > 0 ? item.playCount : nil,
                               lastPlayed: item.lastPlayed,
                               trackNumber: item.trackNumber, discNumber: item.discNumber)
        // User-picked sidecar folder wins (Settings › Metadata Location).
        if let media = resolveURL(item), let (base, release) = sidecarBase(for: media) {
            defer { release() }
            try? JSONEncoder().encode(tags).write(
                to: base.appendingPathExtension("verse").appendingPathExtension("json"),
                options: .atomic)
            return
        }
        guard let (media, release) = sidecarScope(for: item) else { return }
        defer { release() }
        try? JSONEncoder().encode(tags).write(to: SidecarTags.url(besides: media), options: .atomic)
    }

    /// Copy resolved lyrics (the id-keyed cache) to `<file>.lrc` beside the track, once.
    /// Called after the resolver chain lands — LRCLIB fetches end up on disk with the music.
    // ponytail: as with writeTagsSidecar, file-imported loose items lack directory scope, so this
    // write may no-op — their lyrics stay in the id-keyed cache. Upgrade path: folder import.
    func exportLyricsSidecar(_ item: LibraryItem) {
        guard let raw = LyricsResolver.cachedRaw(for: item.id.uuidString), !raw.isEmpty else { return }
        if let media = resolveURL(item), let (base, release) = sidecarBase(for: media) {
            defer { release() }
            let url = base.appendingPathExtension("lrc")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? raw.write(to: url, atomically: true, encoding: .utf8)
            }
            return
        }
        guard let (media, release) = sidecarScope(for: item) else { return }
        defer { release() }
        let url = media.deletingPathExtension().appendingPathExtension("lrc")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? raw.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Count a play. Silently ignores items that aren't in the library — remote playlist entries
    /// are synthesised per play and have ids that were never stored.
    func recordPlay(_ item: LibraryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].playCount += 1
        items[i].lastPlayed = Date()
        save()
        // Play history rides the sidecar too, so a rebuild/wipe can't lose it (restored on
        // re-import). One tiny json per track start — cheap.
        writeTagsSidecar(items[i])
    }

    /// Albums (grouped by `albumKey` — album tag, folder name as fallback) ranked by total
    /// plays. Metadata-first: no disk paths reach the UI.
    /// ponytail: rescans on every call; it's a personal library and Home renders on appear.
    func mostPlayedAlbums(limit: Int = 6) -> [(name: String, plays: Int)] {
        Dictionary(grouping: items.filter { !$0.albumKey.isEmpty }, by: \.albumKey)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.playCount }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (name: $0.0, plays: $0.1) }
    }

    /// Folders to SHOW while browsing: user-created only. Imported source trees stay internal
    /// (identity, sidecar scope, album fallback) — metadata organizes the library; disk layout
    /// and filenames never display (2026-07-21 user request).
    func visibleFolders(at path: [String]) -> [String] {
        Set(customFolders.filter { $0.count > path.count && $0.starts(with: path) }
            .map { $0[path.count] })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func mostPlayedTracks(limit: Int = 6) -> [LibraryItem] {
        items.filter { $0.playCount > 0 }
            .sorted { $0.playCount > $1.playCount }
            .prefix(limit)
            .map { $0 }
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
