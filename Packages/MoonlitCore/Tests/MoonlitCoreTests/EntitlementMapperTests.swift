import XCTest
@testable import MoonlitCore

final class EntitlementMapperTests: XCTestCase {
    func testPremiumPlusTakesPriorityOverPremium() {
        let active = ActiveEntitlements(identifiers: ["premium", "premium_plus"])
        XCTAssertEqual(EntitlementMapper.role(for: active), .premiumPlus)
    }

    func testPremiumOnly() {
        let active = ActiveEntitlements(identifiers: ["premium"])
        XCTAssertEqual(EntitlementMapper.role(for: active), .premium)
    }

    func testNoRecognizedEntitlementReturnsNil() {
        let active = ActiveEntitlements(identifiers: [])
        XCTAssertNil(EntitlementMapper.role(for: active))
    }

    func testUnrelatedEntitlementIsIgnored() {
        let active = ActiveEntitlements(identifiers: ["some_other_addon"])
        XCTAssertNil(EntitlementMapper.role(for: active))
    }
}
