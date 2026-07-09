import SwiftUI
import AppKit

struct MPVPlayerViewRepresentable: NSViewRepresentable {
    let playerView: NSView

    func makeNSView(context: Context) -> MPVPlayerHostView {
        let hostView = MPVPlayerHostView()
        hostView.attach(playerView: playerView)
        return hostView
    }

    func updateNSView(_ nsView: MPVPlayerHostView, context: Context) {
        nsView.attach(playerView: playerView)
    }
}

final class MPVPlayerHostView: NSView {
    private weak var playerView: NSView?

    func attach(playerView newPlayerView: NSView) {
        guard playerView !== newPlayerView || newPlayerView.superview !== self else {
            needsLayout = true
            return
        }

        playerView?.removeFromSuperview()
        newPlayerView.removeFromSuperview()
        newPlayerView.frame = bounds
        newPlayerView.autoresizingMask = [.width, .height]
        addSubview(newPlayerView)
        playerView = newPlayerView
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        guard let playerView else { return }
        playerView.frame = bounds
        playerView.needsLayout = true
        playerView.layoutSubtreeIfNeeded()
    }
}
