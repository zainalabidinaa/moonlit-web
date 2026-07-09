import SwiftUI
import MoonlitCore

/// Full-page / standalone loading state: the spinner plus one randomly
/// chosen caption from `MacLoadingCaptions`, picked once per appearance.
/// Not for use inside buttons or small inline indicators — those should use
/// `MacLottieLoadingView` directly with no caption.
struct MacLoadingView: View {
    var size: CGFloat = 44

    @State private var caption = MacLoadingCaptions.random()

    private var captionSize: CGFloat {
        max(10, min(14, size * 0.28))
    }

    var body: some View {
        VStack(spacing: size * 0.2) {
            MacLottieLoadingView(size: size)
            Text(caption)
                .font(.system(size: captionSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

enum MacLoadingCaptions {
    static let all: [String] = [
        "Buttering the popcorn…",
        "Dimming the lights…",
        "Finding your seat in the dark…",
        "Rolling the opening credits…",
        "Skipping the trailers, unlike the cinema…",
        "Untangling the film reel…",
        "Warming up the projector bulb…",
        "Convincing a server to cooperate…",
        "Negotiating with the streaming gods…",
        "Checking under the couch cushions for a working link…",
        "Politely asking the internet for bandwidth…",
        "Locating the last known copy on Earth…",
        "Consulting the Rotten Tomatoes oracle…",
        "Judging your watch history silently…",
        "Pretending to know what you'll like…",
        "Curating something you'll pretend you didn't cry at…",
        "Cross-referencing your taste with your dignity…",
        "Reading the fine print nobody reads…",
        "Double-checking the ending hasn't changed…",
        "Counting how many times this got nominated and lost…",
        "Confirming this is not, in fact, a rerun…",
        "Untangling a few plot holes…",
        "Waking the algorithm from its nap…",
        "Polishing pixels one by one…",
        "Buffering, but make it cinematic…",
    ]

    static func random() -> String {
        all.randomElement() ?? "Loading…"
    }
}
