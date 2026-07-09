import SwiftUI

/// Harbor's player surface palette — exact oklch→sRGB resolved from
/// `src/index.css` @theme block. Harbor's popovers use fully opaque `elevated`
/// (no alpha); `backdrop-blur-xl` is a no-op on opaque fills, so we match
/// with a pure solid background — no Material, no translucency.
///
/// The app's accent stays white (`MoonlitTheme.accent`) by design.
enum PlayerPalette {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }

    static let canvas = rgb(17, 18, 19)          // #111213  oklch(0.18 0.004 260)
    static let surface = rgb(25, 27, 28)         // #191b1c  oklch(0.22 0.004 260)
    static let elevated = rgb(37, 38, 40)        // #252628  oklch(0.27 0.004 260)
    static let raised = rgb(50, 51, 53)          // #323335  oklch(0.32 0.004 260)

    static let ink = rgb(244, 245, 247)          // #f4f5f7  oklch(0.97 0.003 260)
    static let inkMuted = rgb(163, 165, 166)     // #a3a5a6  oklch(0.72 0.003 260)
    static let inkSubtle = rgb(98, 99, 101)      // #626365  oklch(0.50 0.003 260)

    static let edge = Color(.sRGB, red: 60/255, green: 61/255, blue: 63/255, opacity: 0.55)
    static let edgeSoft = Color(.sRGB, red: 60/255, green: 61/255, blue: 63/255, opacity: 0.25)

    // Harbor-pinned badge tints (sky/amber, from `subtitle-menu.tsx`).
    static let infoTintBg = rgb(56, 189, 248).opacity(0.15)
    static let infoTintText = rgb(186, 230, 253)
    static let infoTintRing = rgb(56, 189, 248).opacity(0.30)
    static let warnTintBg = rgb(251, 191, 36).opacity(0.15)
    static let warnTintText = rgb(253, 230, 138)
    static let warnTintRing = rgb(251, 191, 36).opacity(0.30)
}

extension View {
    /// Harbor's popover/panel chrome: solid `elevated` fill, 1px `edge` border,
    /// and Harbor's exact shadow — `0 24px 60px -18px rgba(0,0,0,0.8)`.
    /// No Material, no translucency — matches Harbor's fully opaque panels.
    func harborPanel(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PlayerPalette.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PlayerPalette.edge, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.8), radius: 30, x: 0, y: 14)
    }
}
