#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.shared.currentMask
    }
}

/// Controls the app-wide orientation lock.
/// Set `currentMask = .all` when the player opens; reset to `.portrait` when it closes.
final class OrientationManager {
    static let shared = OrientationManager()
    var currentMask: UIInterfaceOrientationMask = .portrait
}
#endif
