import SwiftUI
import MoonlitCore

struct SpeedPicker: View {
    @ObservedObject var engine: PlayerEngine

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Text("Playback Speed")
                .font(.caption)
                .foregroundColor(MoonlitTheme.textTertiary)
                .padding(.vertical, 8)

            ForEach(speeds, id: \.self) { speed in
                Button {
                    engine.setPlaybackSpeed(speed)
                } label: {
                    HStack {
                        Text("\(speed, specifier: "%.2f")x")
                            .font(.subheadline)
                            .foregroundColor(engine.playbackSpeed == speed ? .white : MoonlitTheme.textSecondary)
                        Spacer()
                        if engine.playbackSpeed == speed {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(MoonlitTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 140)
        .background(MoonlitTheme.surfaceElevated)
        .cornerRadius(MoonlitTheme.radiusControl)
    }
}
