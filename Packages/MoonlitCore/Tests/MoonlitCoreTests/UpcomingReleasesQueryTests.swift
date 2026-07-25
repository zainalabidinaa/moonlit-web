import XCTest
@testable import MoonlitCore

final class UpcomingReleasesQueryTests: XCTestCase {
    func testMovieParametersSortByNearestUpcomingReleaseFirst() {
        let params = UpcomingReleasesQuery.parameters(mediaKind: .movie, today: "2026-07-25")
        XCTAssertEqual(params["sort_by"], "primary_release_date.asc")
        XCTAssertEqual(params["primary_release_date.gte"], "2026-07-25")
        XCTAssertEqual(params["vote_count.gte"], "5")
    }

    func testTVUsesFirstAirDateField() {
        let params = UpcomingReleasesQuery.parameters(mediaKind: .tv, today: "2026-07-25")
        XCTAssertEqual(params["sort_by"], "first_air_date.asc")
        XCTAssertEqual(params["first_air_date.gte"], "2026-07-25")
    }
}
