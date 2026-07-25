import SwiftUI
import MoonlitCore

struct AudioPickerPanel: View {
    @ObservedObject var engine: PlayerEngine
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(title: "Audio")

            Divider().background(Color.white.opacity(0.15))

            if engine.availableAudioTracks.isEmpty {
                Text("No audio tracks available")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .padding()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(engine.availableAudioTracks, id: \.self) { track in
                            let isSelected = engine.selectedAudioTrack == track
                            Button {
                                engine.setAudioTrack(track)
                                withAnimation(.easeInOut(duration: 0.2)) { isShowing = false }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(track)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(MoonlitTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(width: 210)
        .playerGlassPanel(cornerRadius: MoonlitTheme.radiusCard)
    }

    @ViewBuilder
    private func panelHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isShowing = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .glassCircle(clear: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
