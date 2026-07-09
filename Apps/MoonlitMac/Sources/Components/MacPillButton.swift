import SwiftUI
import MoonlitCore

/// Shared filter/tab used across the app (streaming-service categories, media
/// gallery tabs, etc.) — a plain text tab with an underline on the active
/// item, no pill/capsule shape, so selection styling stays consistent instead
/// of each screen hand-rolling its own.
struct MacPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(isHovering ? 0.75 : 0.55))
                Rectangle()
                    .fill(isSelected ? Color.white : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
