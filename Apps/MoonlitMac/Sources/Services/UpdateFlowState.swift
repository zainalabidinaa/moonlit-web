import Foundation

/// Plain-value snapshot of the `SUAppcastItem` currently being offered, so the
/// SwiftUI layer doesn't need to import Sparkle's ObjC types directly.
struct UpdateItemInfo {
    let displayVersion: String
    let notesHTML: String?
    let isCritical: Bool
    let isInformationOnly: Bool
}

/// Mirrors the phases `SPUUserDriver` walks a user driver through, holding
/// just enough to render `UpdateFlowView`. The reply/cancellation closures
/// Sparkle hands us live alongside each phase in `UpdateFlowState` rather
/// than inside the enum, since they aren't meaningfully comparable state.
enum UpdatePhase {
    case checking
    case updateAvailable(UpdateItemInfo)
    case downloading(progress: Double?)
    case extracting(progress: Double?)
    case readyToInstall
    case installing(applicationTerminated: Bool)
    case installed(relaunched: Bool)
    case notFound(message: String)
    case error(message: String)
    case permissionRequest
}

/// Bridges Sparkle's `SPUUserDriver` callbacks (delivered on the main actor,
/// but from `MoonlitUpdateUserDriver`, an `NSObject`) into SwiftUI. One
/// instance is shared between `MoonlitUpdateUserDriver` and `UpdateFlowView`.
@MainActor
final class UpdateFlowState: ObservableObject {
    @Published var phase: UpdatePhase?

    var onChoice: ((SparkleChoice) -> Void)?
    var onPermissionReply: ((_ automaticallyChecks: Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onAcknowledge: (() -> Void)?

    private var expectedContentLength: UInt64?
    private var receivedLength: UInt64 = 0

    func reset() {
        phase = nil
        onChoice = nil
        onPermissionReply = nil
        onCancel = nil
        onAcknowledge = nil
        expectedContentLength = nil
        receivedLength = 0
    }

    func beginDownloadProgress(expectedContentLength: UInt64?) {
        self.expectedContentLength = expectedContentLength
        receivedLength = 0
    }

    func addDownloadedBytes(_ length: UInt64) {
        receivedLength += length
        guard let expected = expectedContentLength, expected > 0 else {
            phase = .downloading(progress: nil)
            return
        }
        phase = .downloading(progress: min(1, Double(receivedLength) / Double(expected)))
    }
}

/// Swift-friendly mirror of `SPUUserUpdateChoice`, so `UpdateFlowView` doesn't
/// need to import Sparkle.
enum SparkleChoice {
    case install
    case dismiss
    case skip
}
