import Foundation

public struct MoonlitProfile: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let userId: String
    public let name: String
    public let avatarColor: String?
    public let avatarId: Int?
    public let profileIndex: Int
    public let usesPrimaryAddons: Bool
    public let pinEnabled: Bool
    public let role: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case userId = "user_id"
        case avatarColor = "avatar_color"
        case avatarId = "avatar_id"
        case profileIndex = "profile_index"
        case usesPrimaryAddons = "uses_primary_addons"
        case pinEnabled = "pin_enabled"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        userId: String,
        name: String,
        avatarColor: String? = nil,
        avatarId: Int? = nil,
        profileIndex: Int = 0,
        usesPrimaryAddons: Bool = true,
        pinEnabled: Bool = false,
        role: String = "user",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.avatarColor = avatarColor
        self.avatarId = avatarId
        self.profileIndex = profileIndex
        self.usesPrimaryAddons = usesPrimaryAddons
        self.pinEnabled = pinEnabled
        self.role = role
        self.createdAt = createdAt
    }

    public var isAdmin: Bool { role == "admin" }

    public var profileRole: ProfileRole {
        // The portal/backend is the source of truth for role names ("premium",
        // "premium_plus"). Map the older app-only names as legacy aliases so any
        // pre-existing rows keep resolving correctly.
        switch role {
        case "premium_full":        return .premium
        case "premium_self_manage": return .premiumPlus
        default:                    return ProfileRole(rawValue: role) ?? .user
        }
    }
}

public enum ProfileRole: String, Codable, Sendable, CaseIterable {
    case admin            = "admin"
    case friendsAndFamily = "friends_family"
    case premium          = "premium"
    case premiumPlus      = "premium_plus"
    case free             = "free"
    case restricted       = "restricted"
    case user             = "user"

    public var isRestricted: Bool {
        self == .restricted
    }

    public var canBrowse: Bool {
        self != .restricted
    }

    /// True when the user may add & manage their OWN addons (bring-your-own,
    /// including their own stream addon URL). Other roles get addons provisioned
    /// for them but cannot add their own. Admin + Premium+ (self-manage) only.
    public var canManageOwnAddons: Bool {
        self == .admin || self == .premiumPlus
    }

    public var canManageCatalogs: Bool { self == .admin }
    public var showsAdminTab: Bool     { self == .admin }

    public var displayName: String {
        switch self {
        case .admin:             return "Admin"
        case .friendsAndFamily:  return "Friends & Family"
        case .premium:           return "Premium"
        case .premiumPlus:       return "Premium+"
        case .free:              return "Free"
        case .restricted:        return "Restricted"
        case .user:              return "User"
        }
    }
}

public struct UserSession: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userId: String
    public let email: String?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        userId: String,
        email: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
        self.email = email
    }

    public var isExpired: Bool { Date() >= expiresAt }
}
