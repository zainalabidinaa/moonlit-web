import XCTest
@testable import MoonlitCore

final class ProfileRoleTests: XCTestCase {
    func testHasPremiumAccess() {
        XCTAssertTrue(ProfileRole.admin.hasPremiumAccess)
        XCTAssertTrue(ProfileRole.friendsAndFamily.hasPremiumAccess)
        XCTAssertTrue(ProfileRole.premium.hasPremiumAccess)
        XCTAssertTrue(ProfileRole.premiumPlus.hasPremiumAccess)
        XCTAssertFalse(ProfileRole.free.hasPremiumAccess)
        XCTAssertFalse(ProfileRole.user.hasPremiumAccess)
        XCTAssertFalse(ProfileRole.restricted.hasPremiumAccess)
    }
}
