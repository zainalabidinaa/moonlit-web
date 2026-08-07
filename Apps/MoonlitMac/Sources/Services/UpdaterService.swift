import Foundation
import Sparkle

/// Thin ObservableObject wrapper around a Sparkle `SPUUpdater`, so SwiftUI
/// views (menu commands, the Settings row) can drive it without touching
/// AppKit/Sparkle types directly.
///
/// Moonlit isn't on the Mac App Store, so Sparkle owns the actual
/// check → download → verify → install mechanics. The update UI itself
/// (release notes, progress, install prompts) is Moonlit's own —
/// `MoonlitUpdateUserDriver` + `UpdateFlowView` — rather than Sparkle's
/// stock AppKit alerts, so it matches the app's dark theme. This is
/// separate from `WhatsNewView`, the branded "what's new" announcement
/// shown on first launch after an update installs.
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    @Published private(set) var lastUpdateCheckDate: Date?

    private let updater: SPUUpdater
    private let userDriver: MoonlitUpdateUserDriver
    /// Sparkle's delegate is only settable at `SPUUpdater` init time, which
    /// runs before `self` exists — this proxy is created first and wired to
    /// `self` right after, so Sparkle's callbacks still reach this instance.
    private let feedProvider = UpdaterFeedProvider()

    private init() {
        automaticallyChecksForUpdates = true
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Moonlit"
        userDriver = MoonlitUpdateUserDriver(appName: appName)
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: feedProvider
        )
        feedProvider.owner = self

        do {
            try updater.start()
        } catch {
            assertionFailure("Sparkle updater failed to start: \(error)")
        }

        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    fileprivate func updateCycleFinished(lastCheckDate: Date?) {
        lastUpdateCheckDate = lastCheckDate
    }
}

private final class UpdaterFeedProvider: NSObject, SPUUpdaterDelegate {
    weak var owner: UpdaterService?

    /// Points Sparkle at the appcast without needing an `SUFeedURL` entry in
    /// the generated Info.plist. See `docs/updates.md` for hosting the feed.
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://trymoonlit.app/appcast.xml"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor [owner] in
            owner?.updateCycleFinished(lastCheckDate: updater.lastUpdateCheckDate)
        }
    }
}
