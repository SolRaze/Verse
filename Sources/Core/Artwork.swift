import AVFoundation
import UIKit

/// Embedded cover art for local files, extracted once and cached as a small jpeg keyed by the
/// library item id. Rows read it synchronously from an in-memory cache; the disk file is the
/// backing store so it survives relaunches without re-decoding every media file.
///
/// ponytail: 200px thumbnails, jpeg. Good enough for a 44pt row and a 600px CarPlay canvas; store
/// full-res only if a use for it shows up.
enum Artwork {
    // NSCache is internally synchronized; the compiler just can't see it.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    private static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func file(for key: String) -> URL {
        dir.appendingPathComponent(key + ".jpg")
    }

    static func exists(for key: String) -> Bool {
        cache.object(forKey: key as NSString) != nil
            || FileManager.default.fileExists(atPath: file(for: key).path)
    }

    /// Cheap: memory cache, then disk. Returns nil when the file has no embedded art.
    static func image(for key: String) -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: file(for: key).path) else { return nil }
        cache.setObject(img, forKey: key as NSString)
        return img
    }

    /// Extract + cache. No-op if already done or the file carries no artwork.
    static func store(from mediaURL: URL, key: String) async {
        guard !exists(for: key) else { return }
        let asset = AVURLAsset(url: mediaURL)
        guard let metadata = try? await asset.load(.metadata) else { return }
        for item in metadata where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue), let img = UIImage(data: data) else { continue }
            let thumb = img.preparingThumbnail(of: CGSize(width: 200, height: 200)) ?? img
            if let jpg = thumb.jpegData(compressionQuality: 0.8) {
                try? jpg.write(to: file(for: key))
                cache.setObject(thumb, forKey: key as NSString)
            }
            return
        }
    }
}
