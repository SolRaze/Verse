import XCTest
import UIKit
@testable import Verse

/// "Colour From Cover" (inbox-3): a solid-red cover must yield a red-ish accent, not grey.
final class DominantColorTests: XCTestCase {
    func testRedImageGivesRedAccent() throws {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let c = try XCTUnwrap(Artwork.dominantColor(img))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        XCTAssertGreaterThan(r, g + 0.3)   // clearly red-dominant
        XCTAssertGreaterThan(r, b + 0.3)
    }
}

/// In-place metadata (inbox-3): sidecar tags win over filename parsing, and a re-import keeps
/// item identity so play counts / likes / id-keyed caches survive.
@MainActor
final class SidecarTests: XCTestCase {

    func testSidecarReadAndReimportKeepsIdentity() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("SidecarTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("not really audio".utf8).write(to: root.appendingPathComponent("Nobody - Placeholder.mp3"))
        try Data(#"{"title":"Real Title","artist":"Real Artist","liked":true,"album":"Real Album","playCount":5}"#.utf8)
            .write(to: root.appendingPathComponent("Nobody - Placeholder.verse.json"))

        let store = LibraryStore()
        let rootName = root.lastPathComponent
        defer { store.removeFolder([rootName]) }   // keep the test-host library clean

        store.add(pickedURLs: [root])
        let first = try XCTUnwrap(store.items.first { $0.folders == [rootName] })
        XCTAssertEqual(first.title, "Real Title")     // sidecar beat the filename parse
        XCTAssertEqual(first.artist, "Real Artist")
        XCTAssertTrue(first.liked)
        XCTAssertEqual(first.album, "Real Album")     // album rides the sidecar
        XCTAssertEqual(first.playCount, 5)            // play history restored (rebuild path)

        store.recordPlay(first)
        store.add(pickedURLs: [root])                 // re-import the same tree
        let again = try XCTUnwrap(store.items.first { $0.folders == [rootName] })
        XCTAssertEqual(again.id, first.id)            // identity survived
        XCTAssertEqual(again.playCount, 6)            // in-app history beats the sidecar's
    }
}
