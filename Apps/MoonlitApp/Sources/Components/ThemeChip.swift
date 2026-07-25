import SwiftUI
import MoonlitCore

struct ThemeChip: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.palette().primary)
                        .frame(width: 40, height: 40)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.palette().onPrimary)
                    }
                }
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundColor(isSelected ? MoonlitTheme.accent : MoonlitTheme.textSecondary)
                if isSelected {
                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusSmall)
                        .fill(MoonlitTheme.accent)
                        .frame(width: 20, height: 3)
                } else {
                    Spacer().frame(height: 3)
                }
            }
        }
    }
}
