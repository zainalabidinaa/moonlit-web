import SwiftUI
import AppKit

/// Custom hover-reactive window controls that replace the native traffic
/// lights. They sit at the window's top-right, styled like the player's flat
/// chrome buttons (monochrome glyphs). Each button reacts to hover
/// *independently* — only the glyph you point at brightens — and each has a
/// generous circular hit area so clicks register without hunting for the glyph.
struct MacWindowControls: View {
    @State private var window: NSWindow?

    var body: some View {
        HStack(spacing: 4) {
            WindowChromeButton(systemName: "minus", label: "Minimize", tint: Self.amber) {
                window?.performMiniaturize(nil)
            }
            WindowChromeButton(systemName: "square", label: "Zoom", tint: Self.green) {
                window?.zoom(nil)
            }
            WindowChromeButton(systemName: "xmark", label: "Close", tint: Self.red) {
                window?.performClose(nil)
            }
        }
        .background(WindowAccessor { resolved in
            if window == nil { window = resolved }
        })
    }

    // Traffic-light hues, used as glyph tints + hover halos.
    static let red = Color(red: 0.886, green: 0.412, blue: 0.361)
    static let amber = Color(red: 0.878, green: 0.694, blue: 0.333)
    static let green = Color(red: 0.373, green: 0.710, blue: 0.514)
}

/// A single flat window-chrome button. Its glyph carries a dimmed traffic-light
/// tint at rest; hovering lights the glyph fully and blooms a soft radial halo
/// of the same hue behind the generous circular hit area.
private struct WindowChromeButton: View {
    let systemName: String
    let label: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    private let glyphSize: CGFloat = 28
    private let hitSize: CGFloat = 40

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(isHovering ? 0.34 : 0), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: hitSize * 0.5
                        )
                    )
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint.opacity(isHovering ? 1.0 : 0.72))
            }
            .frame(width: glyphSize, height: glyphSize)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

/// Persistent back affordance for pushed sub-views. A labeled clear
/// liquid-glass pill using the same material as the nav pill, so the two read
/// as a single row. Aligned to the nav pill's baseline in `MacMainView`.
struct MacBackButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isHovering ? 1.0 : 0.85))
            .padding(.leading, 12)
            .padding(.trailing, 15)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .macLiquidGlassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

/// Resolves the hosting NSWindow so the custom controls can drive it.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onResolve(window) }
        }
    }
}
