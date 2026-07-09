import SwiftUI
import AVKit

/// Wraps AVKit's `AVRoutePickerView`. On macOS this controls the system
/// CoreAudio default output device (the same picker System Settings → Sound
/// uses) — it doesn't require an `AVPlayer`/`AVAudioSession`, so it works for
/// mpv's audio output too, since mpv plays through whatever CoreAudio reports
/// as the default device.
struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        view.setRoutePickerButtonColor(.white, for: .active)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
