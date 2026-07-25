import UIKit

/// Test-only switches driven by launch arguments so UI automation
/// (agent-device / XCUITest) can drive a quiescent app.
///
/// Inert in production: the flag is only true when the argument is passed at
/// launch. Continuously-running animations (hero auto-advance, looping pulses,
/// the splash star field) keep the run loop busy, which blocks XCUITest's
/// idle synchronization and makes taps/snapshots time out.
enum UITestMode {
    /// Pass `-uiTestDisableAnimations` at launch to stop continuous/auto
    /// animations so the app reaches an idle state between interactions.
    static let disableContinuousAnimations =
        ProcessInfo.processInfo.arguments.contains("-uiTestDisableAnimations")
}
