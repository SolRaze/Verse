import AVFoundation
import UIKit

/// Embedded cover art for local files, extracted once and cached as a small jpeg keyed by the
/// library item id. Rows read it synchronously from an in-memory cache; the disk file is the
/// backing store so it survives relaunches without re-decoding every media file.
///
/// 600px jpegs since 2026-07-21 (was 200) — the player pane and CarPlay canvas draw the same
/// cached file, and 200px looked soft there. Rows still render it at 28–56pt happily.
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
    /// A miss writes an empty file so the next play doesn't re-load AVAsset metadata (issue #4).
    /// ponytail: the negative marker is permanent; "Fetch Metadata" clears it via invalidate().
    static func store(from mediaURL: URL, key: String) async {
        guard !exists(for: key) else { return }
        let asset = AVURLAsset(url: mediaURL)
        let metadata = (try? await asset.load(.metadata)) ?? []
        for item in metadata where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue), let img = UIImage(data: data) else { continue }
            let thumb = img.preparingThumbnail(of: CGSize(width: 600, height: 600)) ?? img
            if let jpg = thumb.jpegData(compressionQuality: 0.8) {
                try? jpg.write(to: file(for: key))
                cache.setObject(thumb, forKey: key as NSString)
            }
            return
        }
        try? Data().write(to: file(for: key))
    }

    /// Cache a supplied image (e.g. an online cover) the same way extracted art is stored: a
    /// 200px jpeg on disk plus the memory cache. Caller invalidates first when replacing.
    static func store(image: UIImage, key: String) {
        let thumb = image.preparingThumbnail(of: CGSize(width: 600, height: 600)) ?? image
        guard let jpg = thumb.jpegData(compressionQuality: 0.8) else { return }
        try? jpg.write(to: file(for: key))
        cache.setObject(thumb, forKey: key as NSString)
    }

    /// Average colour of an image, saturation/brightness nudged up so it reads as an accent on
    /// black (a raw average is often muddy). For the "Colour From Cover" lyrics tint (inbox-3).
    /// ponytail: CIAreaAverage — one pixel, no palette clustering; swap for a vibrant-colour
    /// pass if the average reads too grey on real covers.
    static func dominantColor(_ image: UIImage) -> UIColor? {
        guard let input = CIImage(image: image) else { return nil }
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        guard let out = filter?.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                blue: CGFloat(px[2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return UIColor(hue: h, saturation: min(1, s * 1.6 + 0.15),
                       brightness: min(1, max(b, 0.7)), alpha: 1)
    }

    /// Drop the cached thumbnail (or a negative marker) so the next store() re-extracts.
    static func invalidate(key: String) {
        cache.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: file(for: key))
    }
}
