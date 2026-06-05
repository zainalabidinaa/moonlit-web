import SwiftUI
import AVKit
import LunaCore

struct PlayerScreen: View {
    let launch: PlayerLaunch
    let onDismiss: () -> Void

    @StateObject private var engine = PlayerEngine.shared
    @State private var showControls = true
    @State private var gestureState = PlayerGestureState()
    @State private var isLocked = false
    @State private var showUnlockHint = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = engine.player {
                EnginePlayerView(player: player)
                    .ignoresSafeArea()
                    .playerGestures(
                        engine: engine,
                        state: $gestureState,
                        showControls: $showControls,
                        isLocked: $isLocked
                    )
            } else if engine.isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(LunaTheme.textSecondary)
                }
            }

            PlayerFeedbackPill(mode: gestureState.mode, value: feedbackText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            PlayerLockMode(isLocked: $isLocked, showHint: $showUnlockHint)

            if showControls && !isLocked {
                VStack {
                    // Top bar
                    HStack {
                        Button {
                            engine.stop()
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .glassCircle(clear: true)

                        Spacer()

                        VStack(spacing: 2) {
                            Text(launch.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if engine.duration > 0 {
                                Text(timeRemaining)
                                    .font(.caption)
                                    .foregroundColor(LunaTheme.textSecondary)
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation { isLocked.toggle() }
                        } label: {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .glassCircle(clear: true)

                        Button { /* ellipsis */ } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .glassCircle(clear: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 56)

                    Spacer()

                    // Bottom transport
                    VStack(spacing: 12) {
                        // Progress
                        VStack(spacing: 6) {
                            if #available(iOS 26, *) {
                                Slider(
                                    value: Binding(
                                        get: { engine.currentPosition },
                                        set: { engine.seek(to: $0) }
                                    ),
                                    in: 0...max(engine.duration, 1)
                                )
                                .labelsHidden()
                                .tint(.white)
                                .controlSize(.large)
                            } else {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.20))
                                            .frame(height: 4)
                                        Capsule()
                                            .fill(Color.white)
                                            .frame(
                                                width: engine.duration > 0
                                                    ? min(geo.size.width * (engine.currentPosition / max(engine.duration, 0.001)), geo.size.width)
                                                    : 0,
                                                height: 4
                                            )
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 14, height: 14)
                                            .offset(x: engine.duration > 0
                                                ? min(geo.size.width * (engine.currentPosition / max(engine.duration, 0.001)) - 7, geo.size.width - 7)
                                                : -7)
                                    }
                                }
                                .frame(height: 32)
                            }

                            HStack {
                                Text(formatTime(engine.currentPosition))
                                Spacer()
                                Text("-\(formatTime(max(engine.duration - engine.currentPosition, 0)))")
                            }
                            .font(.caption)
                            .foregroundColor(LunaTheme.textSecondary)
                        }

                        PlayerBottomBar(
                            engine: engine,
                            hasMultipleSources: true,
                            hasEpisodes: launch.seasonNumber != nil,
                            hasExternalUrl: false
                        )
                        .padding(.bottom, 40)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.launch(launch)
            engine.play()
        }
        .onDisappear {
            engine.stop()
        }
    }

    private var feedbackText: String {
        switch gestureState.mode {
        case .brightness: return "\(Int(gestureState.value * 100))%"
        case .volume: return "\(Int(gestureState.value * 100))%"
        case .horizontalSeek:
            let h = Int(gestureState.value) / 3600
            let m = (Int(gestureState.value) % 3600) / 60
            let s = Int(gestureState.value) % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        case .none: return ""
        }
    }

    private var timeRemaining: String {
        let remaining = max(engine.duration - engine.currentPosition, 0)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds)) remaining"
        }
        return "\(minutes):\(String(format: "%02d", seconds)) remaining"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - AVPlayer UIKit Wrapper

struct EnginePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
