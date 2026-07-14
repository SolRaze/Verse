import Foundation

/// One timed line of an LRC file.
struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

struct Lyrics: Equatable {
    var lines: [LyricLine]      // sorted by time; empty when only plain text exists
    var plain: String?
    var offset: TimeInterval    // LRC `[offset:]`, milliseconds in the file, seconds here

    var isSynced: Bool { !lines.isEmpty }

    /// Index of the line that should be showing at `position`, or nil before the first line.
    func lineIndex(at position: TimeInterval) -> Int? {
        let t = position - offset
        guard let first = lines.first, t >= first.time else { return nil }
        // ponytail: linear scan. Lines are hundreds at most; binary search if a 10k-line file appears.
        var found = 0
        for (i, line) in lines.enumerated() where line.time <= t { found = i }
        return found
    }
}

// MARK: - LRC parsing

enum LRCParser {
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

    /// Parses LRC text. Tolerates multiple timestamps per line, metadata tags, blank lines,
    /// and unsorted input. Returns plain-text lyrics if no timestamps are found at all.
    static func parse(_ raw: String) -> Lyrics {
        var lines: [LyricLine] = []
        var offset: TimeInterval = 0

        for rawLine in raw.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let stamps = tagPattern.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))

            if stamps.isEmpty {
                if let ms = offsetTag(in: rawLine) { offset = ms }
                continue
            }

            // Text is whatever follows the final timestamp on the line.
            let textStart = stamps.last!.range.upperBound
            let text = ns.substring(from: textStart).trimmingCharacters(in: .whitespaces)

            for stamp in stamps {
                guard let time = seconds(from: stamp, in: ns) else { continue }
                lines.append(LyricLine(time: time, text: text))
            }
        }

        lines.sort { $0.time < $1.time }

        if lines.isEmpty {
            let plain = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return Lyrics(lines: [], plain: plain.isEmpty ? nil : plain, offset: 0)
        }
        return Lyrics(lines: lines, plain: nil, offset: offset)
    }

    private static func seconds(from match: NSTextCheckingResult, in ns: NSString) -> TimeInterval? {
        guard let min = Double(ns.substring(with: match.range(at: 1))),
              let sec = Double(ns.substring(with: match.range(at: 2))) else { return nil }
        var frac: Double = 0
        if match.range(at: 3).location != NSNotFound {
            let digits = ns.substring(with: match.range(at: 3))
            // "5" -> .5, "50" -> .50, "500" -> .500
            frac = (Double(digits) ?? 0) / pow(10, Double(digits.count))
        }
        return min * 60 + sec + frac
    }

    /// `[offset:+500]` / `[offset:-250]` — milliseconds, positive means lyrics appear earlier.
    private static func offsetTag(in line: String) -> TimeInterval? {
        guard let r = line.range(of: #"\[offset:\s*([+-]?\d+)\s*\]"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let digits = line[r].filter { $0.isNumber || $0 == "-" || $0 == "+" }
        guard let ms = Double(digits) else { return nil }
        return -ms / 1000
    }
}

// MARK: - LRCLIB

/// https://lrclib.net/docs — no auth, no key. Asks callers to send a real User-Agent.
struct LRCLibClient {
    var session: URLSession = .shared
    var userAgent = "Roadie/1.0 (personal media player)"

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    struct Query {
        var track: String
        var artist: String
        var album: String? = nil
        var duration: TimeInterval? = nil
    }

    func fetch(_ q: Query) async throws -> Lyrics? {
        if let exact = try await get(q) { return exact }
        return try await search(q)
    }

    /// Exact lookup. 404 is a normal "no match", not an error.
    private func get(_ q: Query) async throws -> Lyrics? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: q.track),
            URLQueryItem(name: "artist_name", value: q.artist),
            q.album.map { URLQueryItem(name: "album_name", value: $0) },
            q.duration.map { URLQueryItem(name: "duration", value: String(Int($0.rounded()))) },
        ].compactMap { $0 }

        let (data, resp) = try await session.data(for: request(c.url!))
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return lyrics(from: try JSONDecoder().decode(Response.self, from: data))
    }

    /// Fuzzy fallback. Picks the candidate whose duration is closest to ours, within 5s.
    private func search(_ q: Query) async throws -> Lyrics? {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name: "q", value: "\(q.artist) \(q.track)")]

        let (data, resp) = try await session.data(for: request(c.url!))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let hits = try JSONDecoder().decode([Response].self, from: data)

        let best: Response?
        if let want = q.duration {
            best = hits
                .filter { $0.syncedLyrics != nil }
                .min { abs(($0.duration ?? .infinity) - want) < abs(($1.duration ?? .infinity) - want) }
                .flatMap { abs(($0.duration ?? .infinity) - want) <= 5 ? $0 : nil }
        } else {
            best = hits.first { $0.syncedLyrics != nil } ?? hits.first
        }
        return best.flatMap(lyrics(from:))
    }

    private func lyrics(from r: Response) -> Lyrics? {
        if let synced = r.syncedLyrics, !synced.isEmpty { return LRCParser.parse(synced) }
        if let plain = r.plainLyrics, !plain.isEmpty { return Lyrics(lines: [], plain: plain, offset: 0) }
        return nil
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }
}
