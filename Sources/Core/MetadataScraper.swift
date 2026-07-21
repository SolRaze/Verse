import Foundation
import UIKit

/// Online metadata lookup: MusicBrainz for title/artist/album, Cover Art Archive for the cover.
/// Free, no API key. Opt-in (Pref.onlineMetadata) — only runs when the user hits Fetch Metadata
/// with the toggle on. MusicBrainz rejects requests without a User-Agent, so every call sets one.
struct MetadataScraper {
    struct Result {
        var title: String
        var artist: String
        var album: String?
        var coverImage: UIImage?
    }

    /// The subset of a MusicBrainz `recording` search we use. Value-typed and Sendable so the
    /// pure parse below is trivially testable offline.
    struct Parsed: Sendable, Equatable {
        var title: String
        var artist: String
        var album: String?
        var releaseMBID: String?
    }

    private static let userAgent = "Verse/0.1 ( github.com/SolRaze/Verse )"

    /// Artist portrait via Deezer's keyless search API (MusicBrainz carries no images).
    /// ponytail: first hit wins; wrong-artist collisions are the user's cue to rename tags.
    static func artistImage(named name: String) async -> UIImage? {
        var comps = URLComponents(string: "https://api.deezer.com/search/artist")!
        comps.queryItems = [.init(name: "q", value: name), .init(name: "limit", value: "1")]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (obj["data"] as? [[String: Any]])?.first,
              let pic = (first["picture_xl"] as? String) ?? (first["picture_big"] as? String),
              let picURL = URL(string: pic),
              let (img, _) = try? await URLSession.shared.data(from: picURL)
        else { return nil }
        return UIImage(data: img)
    }

    /// Pure: MusicBrainz recording-search JSON -> top hit. Nil when there are no recordings.
    /// ponytail: JSONSerialization dictionary-walk, not a Codable model — one shape, one caller.
    static func parse(_ data: Data) -> Parsed? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rec = (root["recordings"] as? [[String: Any]])?.first else { return nil }
        let title = rec["title"] as? String ?? ""
        let artist = (rec["artist-credit"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }.joined() ?? ""
        let release = (rec["releases"] as? [[String: Any]])?.first
        return Parsed(title: title, artist: artist,
                      album: release?["title"] as? String,
                      releaseMBID: release?["id"] as? String)
    }

    /// Lucene query for the recording search. Pure + testable. THE 2026-07-21 bug: an empty
    /// artist used to emit `artist:""`, which matches nothing — every filename-parsed track
    /// (artist unknown) failed, i.e. "fetch never worked". Empty fields are omitted now, and
    /// embedded quotes are stripped so they can't break the query syntax.
    static func buildQuery(title: String, artist: String, filename: String) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: " ") }
        var parts: [String] = []
        if !title.isEmpty { parts.append("recording:\"\(esc(title))\"") }
        if !artist.isEmpty { parts.append("artist:\"\(esc(artist))\"") }
        if parts.isEmpty { parts.append("recording:\"\(esc(filename))\"") }
        return parts.joined(separator: " AND ")
    }

    /// Search MusicBrainz, then fetch the release's front cover. Falls back to the filename when
    /// tags are empty. Returns nil on any network/parse failure — the caller keeps embedded tags.
    static func lookup(title: String, artist: String, filename: String) async -> Result? {
        let query = buildQuery(title: title, artist: artist, filename: filename)

        // Politeness spacing between tracks too — the caller loops the whole library.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var comps = URLComponents(string: "https://musicbrainz.org/ws/2/recording")!
        comps.queryItems = [.init(name: "query", value: query),
                            .init(name: "fmt", value: "json"),
                            .init(name: "limit", value: "1")]
        guard let url = comps.url else { return nil }

        guard let data = await get(url), let parsed = parse(data) else { return nil }

        // ~1s politeness spacing before the second host (MusicBrainz asks callers not to hammer it).
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var cover: UIImage?
        if let mbid = parsed.releaseMBID { cover = await coverArt(mbid: mbid) }
        return Result(title: parsed.title, artist: parsed.artist,
                      album: parsed.album, coverImage: cover)
    }

    /// Cover Art Archive front image, 500px, falling back to full size on 404. Redirects to
    /// archive.org for the bytes — URLSession follows them.
    private static func coverArt(mbid: String) async -> UIImage? {
        for size in ["front-500", "front"] {
            guard let url = URL(string: "https://coverartarchive.org/release/\(mbid)/\(size)"),
                  let data = await get(url), let img = UIImage(data: data) else { continue }
            return img
        }
        return nil
    }

    private static func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
