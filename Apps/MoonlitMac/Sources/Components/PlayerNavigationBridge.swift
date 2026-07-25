import Foundation

/// Bridges the player's separate `WindowGroup` back to the main window's
/// navigation. The player has no `MacDetailView` of its own to push onto —
/// "Open Full Details" sets the pending target here and closes the player
/// window, and the main window (already open behind it) picks it up.
@MainActor
final class PlayerNavigationBridge: ObservableObject {
    static let shared = PlayerNavigationBridge()

    struct Target: Equatable {
        let id: String
        let type: String
        let name: String
    }

    @Published var pendingDetail: Target?

    private init() {}
}
