import XCTest

/// The "fetch never worked" regression: empty artist must not emit `artist:""`.
final class QueryBuilderTests: XCTestCase {
    func testEmptyArtistOmitted() {
        let q = MetadataScraper.buildQuery(title: "Song", artist: "", filename: "f")
        XCTAssertEqual(q, "recording:\"Song\"")
    }
    func testBothPresent() {
        let q = MetadataScraper.buildQuery(title: "Song", artist: "Band", filename: "f")
        XCTAssertEqual(q, "recording:\"Song\" AND artist:\"Band\"")
    }
    func testFilenameFallbackAndQuoteStripping() {
        let q = MetadataScraper.buildQuery(title: "", artist: "", filename: "a \"b\"")
        XCTAssertEqual(q, "recording:\"a  b \"")
    }
}
@testable import Verse

/// Online metadata (inbox-3): the pure MusicBrainz `recording` search parse — offline, no network.
final class MetadataScraperTests: XCTestCase {

    func testParsesRecordingSearch() throws {
        // Canned top-hit slice of a real recording-search response (placeholder values).
        let json = """
        {"count":1,"recordings":[{
          "id":"11111111-1111-1111-1111-111111111111",
          "title":"Placeholder Song",
          "artist-credit":[
            {"name":"First Artist","joinphrase":" & "},
            {"name":"Second Artist"}
          ],
          "releases":[
            {"id":"22222222-2222-2222-2222-222222222222","title":"Placeholder Album"}
          ]
        }]}
        """
        let parsed = try XCTUnwrap(MetadataScraper.parse(Data(json.utf8)))
        XCTAssertEqual(parsed.title, "Placeholder Song")
        XCTAssertEqual(parsed.artist, "First ArtistSecond Artist")   // artist-credit names joined
        XCTAssertEqual(parsed.album, "Placeholder Album")
        XCTAssertEqual(parsed.releaseMBID, "22222222-2222-2222-2222-222222222222")
    }

    func testNoRecordingsYieldsNil() {
        XCTAssertNil(MetadataScraper.parse(Data(#"{"count":0,"recordings":[]}"#.utf8)))
    }
}
