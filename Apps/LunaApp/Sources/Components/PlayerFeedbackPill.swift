import SwiftUI
import LunaCore

struct PlayerFeedbackPill: View {
    let mode: PlayerGestureMode
    let value: String

    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(LunaTheme.accent.opacity(0.6)))

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .opacity(mode == .none ? 0 : 1)
        .onChange(of: mode) { _, newMode in
            if newMode != .none {
                opacity = 1
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
            }
        }
    }

    private var iconName: String {
        switch mode {
        case .brightness: return "sun.max.fill"
        case .volume: return "speaker.wave.2.fill"
        case .horizontalSeek: return "clock.arrow.2.circlepath"
        case .none: return ""
        }
    }
}
