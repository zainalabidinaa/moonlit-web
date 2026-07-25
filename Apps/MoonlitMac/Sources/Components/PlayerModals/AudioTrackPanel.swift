import SwiftUI
import MoonlitCore

/// reference-style audio track picker (`src/components/player/audio-menu`): a
/// solid-surface panel with circle-check track rows (flag + codec/channels)
/// and a delay-sync footer.
struct AudioTrackPanel: View {
    @ObservedObject var engine: MPVPlayerEngine
    let onClose: () -> Void

    private func displayName(for lang: String) -> String {
        guard !lang.isEmpty else { return "" }
        return Locale.current.localizedString(forLanguageCode: lang)?.capitalized ?? lang.uppercased()
    }

    private func subtitle(for track: AudioTrackInfo) -> String {
        var parts: [String] = []
        if !track.lang.isEmpty { parts.append(displayName(for: track.lang)) }
        if !track.codec.isEmpty { parts.append(track.codec) }
        if !track.channels.isEmpty { parts.append(track.channels) }
        if track.isDefault { parts.append("Default") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PlayerPalette.edgeSoft)

            if engine.availableAudioTracks.isEmpty {
                Text("No audio tracks available")
                    .font(.system(size: 12.5))
                    .foregroundColor(PlayerPalette.inkSubtle)
                    .padding(14)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(engine.availableAudioTracks) { track in
                            let isSelected = engine.selectedAudioTrackId == track.id
                            row(flag: LanguageFlag.emoji(for: track.lang), label: track.label,
                                subtitle: subtitle(for: track), isSelected: isSelected) {
                                engine.selectAudioTrack(id: track.id)
                                onClose()
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
            }

            DelayRow(title: "Sync Offset", delay: engine.audioDelaySec,
                     disabled: engine.availableAudioTracks.count < 2, onDelay: engine.setAudioDelay)
        }
        .frame(width: 360)
        .playerChromePanel(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.12), value: engine.selectedAudioTrackId)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Audio").font(.system(size: 14, weight: .semibold)).foregroundColor(PlayerPalette.ink)
                if !engine.availableAudioTracks.isEmpty {
                    Text("\(engine.availableAudioTracks.count)").font(.system(size: 11.5)).foregroundColor(PlayerPalette.inkSubtle)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PlayerPalette.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(PlayerPalette.raised))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    @ViewBuilder
    private func row(flag: String, label: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isSelected ? AnyShapeStyle(MoonlitTheme.accent) : AnyShapeStyle(PlayerPalette.raised))
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                    }
                }
                Text(flag).font(.system(size: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 12.5, weight: .medium)).foregroundColor(PlayerPalette.ink).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle.uppercased())
                            .font(.system(size: 10)).tracking(0.4)
                            .foregroundColor(PlayerPalette.inkSubtle).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(isSelected ? PlayerPalette.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? PlayerPalette.edge : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Shared ±0.1s / reset stepper row used by both the audio and subtitle panels.
struct DelayRow: View {
    let title: String
    let delay: Double
    let disabled: Bool
    let onDelay: (Double) -> Void

    private func round(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(PlayerPalette.ink)
                Spacer()
                Text(delay > 0 ? "+\(String(format: "%.2f", delay))s" : "\(String(format: "%.2f", delay))s")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(delay != 0 ? MoonlitTheme.accent : PlayerPalette.inkMuted)
                if delay != 0 {
                    Button { onDelay(0) } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(PlayerPalette.inkMuted)
                            .frame(width: 24, height: 24)
                            .background(PlayerPalette.raised, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                delayButton("−0.1s") { onDelay(round(delay - 0.1)) }
                delayButton("+0.1s") { onDelay(round(delay + 0.1)) }
            }
        }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(PlayerPalette.edgeSoft).frame(height: 1) }
    }

    private func delayButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(PlayerPalette.inkMuted)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(PlayerPalette.elevated, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
