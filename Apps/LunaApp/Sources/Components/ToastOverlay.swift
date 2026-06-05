import SwiftUI
import LunaCore

public struct ToastOverlay: View {
    @ObservedObject private var presenter = ToastPresenter.shared

    public init() {}

    public var body: some View {
        VStack {
            if presenter.visible, let toast = presenter.current {
                HStack(spacing: 8) {
                    Image(systemName: iconFor(toast.style))
                        .foregroundColor(colorFor(toast.style))
                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LunaTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(LunaTheme.outline, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: presenter.visible)
        .allowsHitTesting(false)
    }

    private func iconFor(_ style: ToastStyle) -> String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func colorFor(_ style: ToastStyle) -> Color {
        switch style {
        case .info: return LunaTheme.accent
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }
}
