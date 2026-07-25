import SwiftUI

/// Top-center player microinteraction (adapted from a reference's stream-check-pill):
/// a few seconds after playback starts it asks whether the stream looks right,
/// and on stall/failure it nudges the viewer to pick another source.
struct MacStreamCheckPill: View {
    enum Variant { case check, stalled, failed }

    let variant: Variant
    var onLooksGood: (() -> Void)? = nil
    let onPickAnother: () -> Void

    private struct Copy {
        let title: String
        let sub: String
        let icon: String
        let accent: Color
    }

    private var copy: Copy {
        switch variant {
        case .check:
            return Copy(title: "Does this stream look right?",
                        sub: "Wrong episode or quality?",
                        icon: "checkmark",
                        accent: .white.opacity(0.85))
        case .stalled:
            return Copy(title: "Stream is taking a while",
                        sub: "Probably not cached. Pick another?",
                        icon: "exclamationmark.circle",
                        accent: Color(red: 0.96, green: 0.62, blue: 0.24))
        case .failed:
            return Copy(title: "Stream failed to load",
                        sub: "Try a different source.",
                        icon: "exclamationmark.circle",
                        accent: Color(red: 0.94, green: 0.27, blue: 0.27))
        }
    }

    var body: some View {
        let c = copy
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(variant == .check ? Color.white.opacity(0.08) : c.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: c.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(c.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(c.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(c.sub)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 6) {
                if variant == .check, let onLooksGood {
                    Button(action: onLooksGood) {
                        Text("Looks good")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onPickAnother) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                        Text("Pick another")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 2)
        }
        .padding(.vertical, 9)
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
