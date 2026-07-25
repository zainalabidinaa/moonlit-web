import SwiftUI

@MainActor
public struct MoonlitTheme {
    public static var primary: Color { .white }
    public static var secondary: Color { .white.opacity(0.82) }
    public static var accent: Color { ThemeManager.shared.accent }

    /// Warm gold used for ratings, laurel badges, and other accents.
    /// Kept separate from `accent` (which stays white by design) so gold usage
    /// is opt-in per element instead of recoloring the whole app.
    public static let ratingGold = Color(red: 0.831, green: 0.686, blue: 0.216)

    public static var background: Color { ThemeManager.shared.background }
    public static var surface: Color { ThemeManager.shared.surface }
    public static var surfaceElevated: Color { ThemeManager.shared.surfaceElevated }
    public static var surfaceContainer: Color { ThemeManager.shared.surfaceContainer }

    public static var textPrimary: Color { .white }
    public static var textSecondary: Color { .white.opacity(0.7) }
    public static var textTertiary: Color { .white.opacity(0.5) }
    public static var outline: Color { .white.opacity(0.08) }
    public static var focusRing: Color { .white.opacity(0.9) }
    public static var focusBackground: Color { .white.opacity(0.12) }

    /// Top clearance for content sitting beneath the floating top navbar.
    public static let navBarTopInset: CGFloat = 60

    /// Corner radius scale — snap new UI to one of these instead of picking an
    /// arbitrary value, so the app doesn't accumulate a dozen near-identical radii.
    public static let radiusSmall: CGFloat = 6
    public static let radiusControl: CGFloat = 10
    public static let radiusCard: CGFloat = 14
    public static let radiusLarge: CGFloat = 18
}

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Glass Effect Modifiers (iOS 26 Liquid Glass)

#if canImport(SwiftUI)
import SwiftUI

public enum AppCardSurface {
    case regular
    case darkGlass
}

@available(iOS 26, macOS 26, tvOS 26, *)
private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

private struct GlassCardFallback: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 10)
    }
}

@available(iOS 26, macOS 26, tvOS 26, *)
private struct GlassCapsuleModifier: ViewModifier {
    let interactive: Bool
    let clear: Bool

    func body(content: Content) -> some View {
        if interactive {
            if clear {
                return content.glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
            } else {
                return content.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
            }
        } else {
            if clear {
                return content.glassEffect(.clear, in: Capsule(style: .continuous))
            } else {
                return content.glassEffect(.regular, in: Capsule(style: .continuous))
            }
        }
    }
}

private struct GlassCapsuleFallback: ViewModifier {
    let clear: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if clear {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(clear ? 0.22 : 0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

@available(iOS 26, macOS 26, tvOS 26, *)
private struct GlassCircleModifier: ViewModifier {
    let clear: Bool

    func body(content: Content) -> some View {
        if clear {
            return content.glassEffect(.clear.interactive(), in: Circle())
        } else {
            return content.glassEffect(.regular.interactive(), in: Circle())
        }
    }
}

private struct GlassCircleFallback: ViewModifier {
    let clear: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if clear {
                    Circle().fill(Color.white.opacity(0.12))
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Circle().stroke(Color.white.opacity(clear ? 0.22 : 0.14), lineWidth: 0.6)
            }
    }
}

// MARK: - Public View Extensions

extension View {
    @ViewBuilder
    public func glassCard(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
        } else {
            self.modifier(GlassCardFallback(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    public func glassCapsule(interactive: Bool = false, clear: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.modifier(GlassCapsuleModifier(interactive: interactive, clear: clear))
        } else {
            self.modifier(GlassCapsuleFallback(clear: clear))
        }
    }

    @ViewBuilder
    public func glassCircle(clear: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.modifier(GlassCircleModifier(clear: clear))
        } else {
            self.modifier(GlassCircleFallback(clear: clear))
        }
    }

    @ViewBuilder
    public func appCardStyle(
        surfaceStyle: AppCardSurface = .regular,
        cornerRadius: CGFloat = 14
    ) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            switch surfaceStyle {
            case .regular:
                self.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
            case .darkGlass:
                self.glassEffect(
                    .clear,
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        } else {
            self.modifier(GlassCardFallback(cornerRadius: cornerRadius))
        }
    }
}

public struct MoonlitPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 14) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 1 : 0.38))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.58)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    @ViewBuilder
    public func glassProminentButtonStyle(
        tint: Color = MoonlitTheme.accent,
        cornerRadius: CGFloat = 14
    ) -> some View {
        self.buttonStyle(MoonlitPrimaryButtonStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Shimmer Skeleton

public struct ShimmerCard: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.10))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.18),
                                Color.white.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .modifier(ShimmerAnimation())
            )
    }
}

private struct ShimmerAnimation: ViewModifier {
    @State private var offset: CGFloat = -400

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5).repeatForever(autoreverses: false)
                ) {
                    offset = 400
                }
            }
    }
}

// MARK: - Empty State View

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(MoonlitTheme.textTertiary)
                .frame(width: 80, height: 80)
                .glassCircle()

            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(MoonlitTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .glassCard(cornerRadius: 12, interactive: true)
                .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State View

public struct ErrorStateView: View {
    let message: String
    let onRetry: (() -> Void)?

    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
                .frame(width: 80, height: 80)
                .glassCircle()

            Text("Something went wrong")
                .font(.headline)
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(MoonlitTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .glassCard(cornerRadius: 12, interactive: true)
                .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
