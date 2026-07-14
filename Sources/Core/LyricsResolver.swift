import AVFoundation
import Foundation

/// The resolution chain from SPEC §3: sidecar .lrc → embedded tag → LRCLIB → nothing.
/// Results cache to disk so the car isn't waiting on network.
enum LyricsResolver {
    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `cacheKey` must be stable per track (library item UUID).
    static func resolve(mediaURL: URL?, title: String, artist: String,
                        duration: TimeInterval?, cacheKey: String) async -> Lyrics? {
        let cacheFile = cacheDir.appendingPathComponent(cacheKey + ".lrc")
        if let cached = try? String(contentsOf: cacheFile, encoding: .utf8) {
            return LRCParser.parse(cached)
        }

        if let raw = sidecar(for: mediaURL) ?? (await embedded(in: mediaURL)) {
            try? raw.write(to: cacheFile, atomically: true, encoding: .utf8)
            return LRCParser.parse(raw)
        }

        // LRCLIB (lrclib.net — tranxuanthang/lrclib public instance).
        let client = LRCLibClient()
        let query = LRCLibClient.Query(track: title, artist: artist, duration: duration)
        if let lyrics = try? await client.fetch(query), let raw = rawText(of: lyrics) {
            try? raw.write(to: cacheFile, atomically: true, encoding: .utf8)
            return lyrics
        }
        return nil
    }

    /// User dropped an .lrc by hand — attach it to a track and cache it.
    static func attach(lrcText: String, cacheKey: String) {
        try? lrcText.write(to: cacheDir.appendingPathComponent(cacheKey + ".lrc"),
                           atomically: true, encoding: .utf8)
    }

    private static func sidecar(for mediaURL: URL?) -> String? {
        guard let mediaURL else { return nil }
        let url = mediaURL.deletingPathExtension().appendingPathExtension("lrc")
        // Security scope covers the picked file, not always its siblings — failure is normal.
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// ID3 USLT / iTunes lyrics via AVAsset. VLC-only containers (ogg/mkv/...) throw — fine.
    /// ponytail: no SYLT support; AVFoundation doesn't expose it. LRCLIB covers synced.
    private static func embedded(in mediaURL: URL?) async -> String? {
        guard let mediaURL else { return nil }
        let asset = AVURLAsset(url: mediaURL)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        let lyricIDs: [AVMetadataIdentifier] = [.id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics]
        for item in metadata where item.identifier.map(lyricIDs.contains) == true {
            if let text = try? await item.load(.stringValue), !text.isEmpty { return text }
        }
        return nil
    }

    /// Serialize lyrics back to LRC text for the cache.
    private static func rawText(of lyrics: Lyrics) -> String? {
        if lyrics.isSynced {
            return lyrics.lines.map { line in
                let m = Int(line.time) / 60, s = line.time.truncatingRemainder(dividingBy: 60)
                return String(format: "[%02d:%05.2f]%@", m, s, line.text)
            }.joined(separator: "\n")
        }
        return lyrics.plain
    }
}
