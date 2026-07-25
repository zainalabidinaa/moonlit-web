import AppKit
import MoonlitCore
@testable import MoonlitMac
import XCTest

final class MoonlitMacResourceTests: XCTestCase {
    func testTileHaloSamplerIgnoresWhiteAndFindsArtworkColor() throws {
        let whitePixel: [UInt8] = [255, 255, 255, 255]
        let warmRedPixel: [UInt8] = [178, 42, 28, 255]
        let pixels = Array(repeating: whitePixel, count: 80).flatMap { $0 }
            + Array(repeating: warmRedPixel, count: 20).flatMap { $0 }

        let sampled = try XCTUnwrap(sampleDominantColor(pixels))
        let rgb = try XCTUnwrap(NSColor(sampled).usingColorSpace(.deviceRGB))

        XCTAssertGreaterThan(rgb.redComponent, rgb.greenComponent * 2)
        XCTAssertGreaterThan(rgb.redComponent, rgb.blueComponent * 2)
    }

    func testTileHaloSamplerDoesNotManufactureWhiteForMonochromeArtwork() {
        let palePixel: [UInt8] = [235, 235, 235, 255]
        let darkPixel: [UInt8] = [22, 22, 22, 255]
        let pixels = Array(repeating: palePixel, count: 60).flatMap { $0 }
            + Array(repeating: darkPixel, count: 40).flatMap { $0 }

        XCTAssertNil(sampleDominantColor(pixels))
    }

    func testAwardWorkMatcherIgnoresCaseAndPunctuation() {
        let titles = ["Malcolm in the Middle", "Breaking Bad", "Trumbo"]

        XCTAssertEqual(ActorAwardWorkMatcher.matchIndex(for: "breaking bad", in: titles), 1)
        XCTAssertEqual(ActorAwardWorkMatcher.matchIndex(for: "Trumbo!", in: titles), 2)
        XCTAssertNil(ActorAwardWorkMatcher.matchIndex(for: "Argo", in: titles))
    }

    func testGenreBrowseItemsDeduplicateAcrossMovieAndShowRailsInSourceOrder() {
        let duplicateMovie = MetaPreview(id: "shared", type: .movie, name: "First version")
        let uniqueMovie = MetaPreview(id: "movie", type: .movie, name: "Movie")
        let duplicateShow = MetaPreview(id: "shared", type: .series, name: "Second version")
        let uniqueShow = MetaPreview(id: "show", type: .series, name: "Show")

        let selection = MacSearchGenreSelection(
            movies: [duplicateMovie, uniqueMovie],
            shows: [duplicateShow, uniqueShow]
        )

        XCTAssertEqual(selection.items(for: .all).map(\.id), ["shared", "movie", "show"])
        XCTAssertEqual(selection.items(for: .all).first?.name, "First version")
    }

    func testGenreBrowseTabsReturnOnlyTheirMediaKind() {
        let movie = MetaPreview(id: "movie", type: .movie, name: "Movie")
        let show = MetaPreview(id: "show", type: .series, name: "Show")
        let selection = MacSearchGenreSelection(movies: [movie], shows: [show])

        XCTAssertEqual(selection.items(for: .movies), [movie])
        XCTAssertEqual(selection.items(for: .shows), [show])
    }

    func testHomeOrganizerAndLoadingAnimationAreBundledAndDecodable() throws {
        let bundle = Bundle.main

        let organizerURL = try XCTUnwrap(bundle.url(forResource: "home-organizer", withExtension: "json"))
        let organizerData = try Data(contentsOf: organizerURL)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: organizerData))

        let animationURL = try XCTUnwrap(bundle.url(
            forResource: "loading-animation-gradient-line-2-colors-1",
            withExtension: "json"
        ))
        let animationData = try Data(contentsOf: animationURL)
        let animationObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: animationData) as? [String: Any])
        XCTAssertEqual(animationObject["v"] as? String, "4.8.0")
    }

    func testMPVPlayerHostViewKeepsPlayerViewFillingBoundsAndReattachesReplacement() {
        let host = MPVPlayerHostView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        let firstPlayerView = NSView(frame: .zero)

        host.attach(playerView: firstPlayerView)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        host.layoutSubtreeIfNeeded()

        XCTAssertTrue(firstPlayerView.superview === host)
        XCTAssertEqual(firstPlayerView.frame, host.bounds)
        XCTAssertEqual(firstPlayerView.autoresizingMask, [.width, .height])

        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 576)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(firstPlayerView.frame, host.bounds)

        let replacementPlayerView = NSView(frame: .zero)
        host.attach(playerView: replacementPlayerView)
        host.layoutSubtreeIfNeeded()

        XCTAssertNil(firstPlayerView.superview)
        XCTAssertTrue(replacementPlayerView.superview === host)
        XCTAssertEqual(replacementPlayerView.frame, host.bounds)
        XCTAssertEqual(replacementPlayerView.autoresizingMask, [.width, .height])
    }
}
