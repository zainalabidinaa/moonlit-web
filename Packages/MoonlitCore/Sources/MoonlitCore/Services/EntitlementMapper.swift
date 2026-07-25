import Foundation

/// A snapshot of which RevenueCat entitlement identifiers are currently active
/// for a user. Deliberately not RevenueCat's own `CustomerInfo` type, so this
/// mapping is testable without mocking the SDK, and `PurchaseService` is the
/// only file that has to know how to build one.
public struct ActiveEntitlements: Sendable, Equatable {
    public let identifiers: Set<String>
    public init(identifiers: Set<String>) { self.identifiers = identifiers }
}

public enum EntitlementMapper {
    public static let premiumEntitlementID = "premium"
    public static let premiumPlusEntitlementID = "premium_plus"

    /// `nil` means no recognized StoreKit entitlement is active. Callers MUST
    /// NOT treat `nil` as "downgrade to free" unconditionally — a `nil` here
    /// could just mean the user was never a StoreKit subscriber (e.g. an
    /// admin-granted friends & family row), which must not be touched.
    public static func role(for active: ActiveEntitlements) -> ProfileRole? {
        if active.identifiers.contains(premiumPlusEntitlementID) { return .premiumPlus }
        if active.identifiers.contains(premiumEntitlementID) { return .premium }
        return nil
    }
}
