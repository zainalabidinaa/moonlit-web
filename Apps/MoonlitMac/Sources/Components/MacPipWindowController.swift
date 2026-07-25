import AppKit

/// mpv has no `AVPictureInPictureController` path (that's tied to
/// `AVPlayerLayer`, iOS/macOS AVFoundation-only) — so
/// Tauri desktop build, "PiP" here means a small floating always-on-top
/// window that owns the existing mpv view, not real video-track PiP.
@MainActor
final class MacPipWindowController: NSWindowController {
    private(set) var isActive = false

    static let defaultSize = NSSize(width: 360, height: 203)

    /// Callers are expected to have already removed `videoView` from the
    /// SwiftUI tree (see `MacPlayerView.togglePip`) before this runs, so the
    /// view arrives here with no superview to fight over.
    func enter(videoView: NSView, chrome: NSView) {
        guard !isActive else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 240, height: 135)

        let content = NSView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        content.autoresizingMask = [.width, .height]
        videoView.removeFromSuperview()
        videoView.frame = content.bounds
        videoView.autoresizingMask = [.width, .height]
        content.addSubview(videoView)
        chrome.frame = content.bounds
        chrome.autoresizingMask = [.width, .height]
        content.addSubview(chrome)
        panel.contentView = content

        window = panel
        isActive = true
        videoView.needsLayout = true
        videoView.layoutSubtreeIfNeeded()
        panel.orderFront(nil)
    }

    /// Detaches the video view from the panel and closes it. The caller flips
    /// `isPipActive` right after this returns, which brings
    /// `MPVPlayerViewRepresentable` back into the SwiftUI tree and lets it
    /// re-adopt the now-unparented view into a fresh container.
    func exit() {
        guard isActive else { return }
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        close()
        window = nil
        isActive = false
    }
}
