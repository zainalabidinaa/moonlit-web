import SwiftUI
import MoonlitCore

enum PlayerGestureMode {
    case none
    case brightness
}

struct PlayerGestureState {
    var mode: PlayerGestureMode = .none
    var initialBrightness: CGFloat = 0
    var value: Double = 0
}

struct PlayerGestureViewModifier: ViewModifier {
    @ObservedObject var engine: PlayerEngine
    @Binding var state: PlayerGestureState
    @Binding var showControls: Bool
    @Binding var isLocked: Bool

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .simultaneousGesture(dragGesture)
#else
        content
#endif
    }

#if os(iOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isLocked else { return }
                let screenWidth = UIScreen.main.bounds.width
                let screenHeight = UIScreen.main.bounds.height
                let startX = value.startLocation.x / screenWidth
                let absDx = abs(value.translation.width)
                let absDy = abs(value.translation.height)

                if state.mode == .none {
                    if absDy > absDx * 1.2, startX < 0.4 {
                        state.mode = .brightness
                        state.initialBrightness = UIScreen.main.brightness
                    }
                }

                if state.mode == .brightness {
                    let delta = (-value.translation.height / screenHeight)
                    state.value = Double(min(max(state.initialBrightness + delta, 0), 1))
                    UIScreen.main.brightness = state.value
                }
            }
            .onEnded { _ in
                state.mode = .none
            }
    }
#endif
}

extension View {
    func playerGestures(
        engine: PlayerEngine,
        state: Binding<PlayerGestureState>,
        showControls: Binding<Bool>,
        isLocked: Binding<Bool>
    ) -> some View {
        modifier(PlayerGestureViewModifier(
            engine: engine,
            state: state,
            showControls: showControls,
            isLocked: isLocked
        ))
    }
}
