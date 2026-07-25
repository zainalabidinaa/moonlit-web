import SwiftUI

/// Hand-drawn drag-track volume slider (ported from MoonlitApp's
/// `GlassVolumeSlider`) — matches the reference custom pointer-drag track rather
/// than a native `Slider`.
struct PlayerVolumeSlider: View {
    @Binding var volume: Float
    let isMuted: Bool
    var width: CGFloat = 72

    private let thumbSize: CGFloat = 12
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width
            let effective = isMuted ? 0 : max(0, min(1, CGFloat(volume)))
            let fillW = trackW * effective
            let thumbX = max(0, min(fillW - thumbSize / 2, trackW - thumbSize))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: max(0, fillW), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard trackW > 0 else { return }
                        volume = Float(max(0, min(1, value.location.x / trackW)))
                    }
            )
        }
        .frame(width: width, height: 28)
    }
}
