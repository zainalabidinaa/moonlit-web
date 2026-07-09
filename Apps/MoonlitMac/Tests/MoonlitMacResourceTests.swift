import AppKit
@testable import MoonlitMac
import XCTest

final class MoonlitMacResourceTests: XCTestCase {
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
