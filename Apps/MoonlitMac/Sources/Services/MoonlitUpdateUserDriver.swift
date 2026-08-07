import AppKit
import SwiftUI
import Sparkle

/// Custom `SPUUserDriver` that replaces Sparkle's stock AppKit alerts with
/// `UpdateFlowView`, hosted in a small borderless window so it matches
/// Moonlit's dark theme instead of a plain Aqua dialog.
///
/// Sparkle calls every method here on the main thread/actor, so it's safe
/// to touch `state` and AppKit directly.
@MainActor
final class MoonlitUpdateUserDriver: NSObject, SPUUserDriver {
    let state = UpdateFlowState()

    private var window: NSWindow?
    private let appName: String

    init(appName: String) {
        self.appName = appName
    }

    // MARK: - Window management

    private func presentWindow() {
        if window == nil {
            let hosting = NSHostingView(rootView: UpdateFlowView(state: state, appName: appName))
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.fullScreenAuxiliary]
            // Transparent, so `UpdateFlowView`'s rounded `macDarkGlassCard`
            // corners show the desktop behind them instead of an opaque
            // square window edge poking out past the glass card's clip.
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.contentView = hosting
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWindow() {
        window?.orderOut(nil)
        state.reset()
    }

    // MARK: - Permission

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        state.phase = .permissionRequest
        state.onPermissionReply = { [weak self] automatic in
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: automatic, sendSystemProfile: false))
            self?.closeWindow()
        }
        presentWindow()
    }

    // MARK: - Checking

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state.phase = .checking
        state.onCancel = { [weak self] in
            cancellation()
            self?.closeWindow()
        }
        presentWindow()
    }

    func showUpdateInFocus() {
        presentWindow()
    }

    // MARK: - Update found

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state userState: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let info = UpdateItemInfo(
            displayVersion: appcastItem.displayVersionString,
            notesHTML: appcastItem.itemDescription,
            isCritical: appcastItem.isCriticalUpdate,
            isInformationOnly: appcastItem.isInformationOnlyUpdate
        )
        state.phase = .updateAvailable(info)
        state.onChoice = { [weak self] choice in
            reply(choice.sparkleValue)
            if choice != .install {
                self?.closeWindow()
            }
        }
        presentWindow()
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Release notes are already embedded in the appcast `<description>`
        // and shown via `showUpdateFound`; this only fires for a separate
        // `releaseNotesURL`, which Moonlit's appcast doesn't use.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // Non-fatal — the embedded description is already shown.
    }

    // MARK: - Not found / errors

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state.phase = .notFound(message: (error as NSError).localizedDescription)
        state.onAcknowledge = { [weak self] in
            acknowledgement()
            self?.closeWindow()
        }
        presentWindow()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state.phase = .error(message: (error as NSError).localizedDescription)
        state.onAcknowledge = { [weak self] in
            acknowledgement()
            self?.closeWindow()
        }
        presentWindow()
    }

    // MARK: - Download

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        state.phase = .downloading(progress: nil)
        state.onCancel = { [weak self] in
            cancellation()
            self?.closeWindow()
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        state.beginDownloadProgress(expectedContentLength: expectedContentLength > 0 ? expectedContentLength : nil)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        state.addDownloadedBytes(length)
    }

    // MARK: - Extraction

    func showDownloadDidStartExtractingUpdate() {
        state.phase = .extracting(progress: nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state.phase = .extracting(progress: progress)
    }

    // MARK: - Install

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        state.phase = .readyToInstall
        state.onChoice = { [weak self] choice in
            reply(choice.sparkleValue)
            if choice != .install {
                self?.closeWindow()
            }
        }
        presentWindow()
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        state.phase = .installing(applicationTerminated: applicationTerminated)
        presentWindow()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        state.phase = .installed(relaunched: relaunched)
        state.onAcknowledge = { [weak self] in
            acknowledgement()
            self?.closeWindow()
        }
        presentWindow()
        // The app is about to relaunch anyway; auto-dismiss so nothing
        // lingers if it doesn't.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.state.onAcknowledge?()
        }
    }

    func dismissUpdateInstallation() {
        closeWindow()
    }
}

private extension SparkleChoice {
    var sparkleValue: SPUUserUpdateChoice {
        switch self {
        case .install: .install
        case .dismiss: .dismiss
        case .skip: .skip
        }
    }
}

extension SparkleChoice: Equatable {}
