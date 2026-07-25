import SwiftUI
import MoonlitCore

///  branded pre-roll shown while a stream resolves and the first
/// video frame buffers.
///
/// A full-bleed crisp backdrop of the title with the original stylized logo
/// centered, breathing with a gentle scale pulse. Shared by `PlayerScreen`
/// and `StreamSelectionScreen` so that tapping Play → video feels like one
/// continuous card with no black gap in between.
///
/// Taps pass through to the underlying player controls. The caller should
/// overlay any dismiss/cancel button on top.
struct PlaybackLoadingView: View {
    /// Best available landscape/fanart/poster URL (pre-prioritized by caller).
    /// Rendered crisp & full-bleed. When nil the view shows pure black.
    let backgroundURL: String?
    /// Original stylized title logo.
    let logoURL: URL?
    /// Plain title, used as a fallback when there is no logo.
    let title: String
    /// When non-nil, shows this static line and stops the pulse — e.g.
    /// "No streams available" once resolution finishes empty.
    var statusOverride: String? = nil

    @State private var pulse = false
    @State private var logoVisible = false

    private var wideBackdropURL: URL? { backgroundURL.flatMap(URL.init) }
    private var isLoading: Bool { statusOverride == nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            backdrop

            //  full-height vertical gradient over a solid black base.
            // Top → bottom: 0% → 30% → 60% → 80% → 90% black.
            LinearGradient(
                colors: [
                    .black.opacity(0.0),
                    .black.opacity(0.3),
                    .black.opacity(0.6),
                    .black.opacity(0.8),
                    .black.opacity(0.9),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                logoOrTitle
                    .opacity(logoVisible ? 1.0 : 0.0)
                    .scaleEffect(isLoading ? (pulse ? 1.06 : 0.98) : 1.0)

                if let statusOverride {
                    Text(statusOverride)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            NSLog("[Moonlit][Loading] backdropURL=\(backgroundURL ?? "nil") logoURL=\(logoURL?.absoluteString ?? "nil")")
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeIn(duration: 0.7)) { logoVisible = true }
            }
            guard isLoading, !UITestMode.disableContinuousAnimations else { return }
            // Deferred a turn so the pulse animates away from a rendered resting
            // state. Setting `pulse` inline folds the change into the same
            // transaction as the first layout pass, and the view simply appears
            // at the end scale with no animation at all.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    // MARK: - Backdrop

    @ViewBuilder private var backdrop: some View {
        if let url = wideBackdropURL {
            CachedAsyncImage(url: url) { phase in
                // `CachedAsyncImage` hangs its fetch off `.task` applied to this
                // closure's result, so every phase must return a real view. An
                // empty ViewBuilder result (no `else`) has no lifecycle to attach
                // to, the task never fires, and the phase stays `.empty` forever —
                // which is why the backdrop never loaded while the logo, which
                // does have a fallback branch, did.
                ZStack {
                    Color.clear
                    if case .success(let img) = phase {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                }
                .animation(.easeIn(duration: 0.5), value: isLoaded(phase))
            }
            .ignoresSafeArea()
            .clipped()
        }
    }

    private func isLoaded(_ phase: AsyncImagePhase) -> Bool {
        if case .success = phase { return true }
        return false
    }

    // MARK: - Logo

    @ViewBuilder private var logoOrTitle: some View {
        if let logoURL {
            CachedAsyncImage(url: logoURL) { phase in
                if case .success(let img) = phase {
                    img.resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 180)
                        .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                        .transition(.opacity)
                } else {
                    titleText
                }
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)
    }
}

#Preview("With logo") {
    PlaybackLoadingView(
        backgroundURL: "https://image.tmdb.org/t/p/w1280/628Dep6AxEtDxjZoGP78TsOxYbK.jpg",
        logoURL: URL(string: "https://image.tmdb.org/t/p/w500/dz7lbS1mcW8c6qjXAcjbEhBfA0M.png"),
        title: "Spider-Man: Across the Spider-Verse"
    )
}

#Preview("Title fallback / no streams") {
    PlaybackLoadingView(
        backgroundURL: nil,
        logoURL: nil,
        title: "Spider-Man: Across the Spider-Verse",
        statusOverride: "No streams available"
    )
}
