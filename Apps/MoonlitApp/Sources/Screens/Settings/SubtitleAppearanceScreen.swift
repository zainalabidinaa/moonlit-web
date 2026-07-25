import SwiftUI
import MoonlitCore

struct SubtitleAppearanceScreen: View {
    @StateObject private var store = SubtitleAppearanceStore.shared
    @Environment(\.dismiss) private var dismiss

    // Local state mirrors store so preview updates live
    @State private var fontSize: Double = SubtitleAppearanceStore.shared.fontSize
    @State private var scale: Double = SubtitleAppearanceStore.shared.scale
    @State private var isBold: Bool = SubtitleAppearanceStore.shared.isBold
    @State private var isItalic: Bool = SubtitleAppearanceStore.shared.isItalic
    @State private var verticalPosition: Double = SubtitleAppearanceStore.shared.verticalPosition
    @State private var horizontalMargin: Double = SubtitleAppearanceStore.shared.horizontalMargin
    @State private var textBlur: Double = SubtitleAppearanceStore.shared.textBlur
    @State private var alignment: SubtitleAlignment = SubtitleAppearanceStore.shared.horizontalAlignment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {

                    subtitlePreviewPanel

                    sectionLabel("Quick Presets")
                    VStack(spacing: 0) {
                        ForEach(SubtitlePreset.allCases, id: \.self) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.displayName)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text(preset.description)
                                            .font(.caption)
                                            .foregroundColor(MoonlitTheme.textSecondary)
                                    }
                                    Spacer()
                                    if store.preset == preset {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(MoonlitTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            if preset != SubtitlePreset.allCases.last {
                                Divider().background(Color.white.opacity(0.08))
                            }
                        }
                    }
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                    .padding(.horizontal, 16)

                    sectionLabel("Font")
                    VStack(spacing: 0) {
                        sliderRow("Font Size", value: $fontSize, range: 12...72, step: 1, format: "%.0f") {
                            store.fontSize = fontSize
                        }
                        Divider().background(Color.white.opacity(0.08))
                        sliderRow("Scale", value: $scale, range: 0.5...2.0, step: 0.1, format: "%.1fx") {
                            store.scale = scale
                        }
                        Divider().background(Color.white.opacity(0.08))
                        toggleRow("Bold", isOn: Binding(
                            get: { isBold },
                            set: { isBold = $0; store.isBold = $0 }
                        ))
                        Divider().background(Color.white.opacity(0.08))
                        toggleRow("Italic", isOn: Binding(
                            get: { isItalic },
                            set: { isItalic = $0; store.isItalic = $0 }
                        ))
                    }
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                    .padding(.horizontal, 16)

                    sectionLabel("Colors")
                    VStack(spacing: 0) {
                        colorRow("Text Color", hex: store.textColorHex) { store.textColorHex = $0 }
                        Divider().background(Color.white.opacity(0.08))
                        colorRow("Outline Color", hex: store.outlineColorHex) { store.outlineColorHex = $0 }
                        Divider().background(Color.white.opacity(0.08))
                        colorRow("Background Color", hex: store.backgroundColorHex) { store.backgroundColorHex = $0 }
                    }
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                    .padding(.horizontal, 16)

                    sectionLabel("Position")
                    VStack(spacing: 0) {
                        sliderRow("Vertical Position", value: $verticalPosition, range: 0...200, step: 1, format: "%.0f") {
                            store.verticalPosition = verticalPosition
                        }
                        Divider().background(Color.white.opacity(0.08))
                        alignmentRow
                        Divider().background(Color.white.opacity(0.08))
                        sliderRow("Horizontal Margin", value: $horizontalMargin, range: 0...100, step: 1, format: "%.0fpx") {
                            store.horizontalMargin = horizontalMargin
                        }
                    }
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                    .padding(.horizontal, 16)

                    sectionLabel("Advanced")
                    VStack(spacing: 0) {
                        sliderRow("Text Blur", value: $textBlur, range: 0...5, step: 0.1, format: "%.1f") {
                            store.textBlur = textBlur
                        }
                        Divider().background(Color.white.opacity(0.08))
                        toggleRow("Scale with Window Size", isOn: Binding(
                            get: { store.scaleWithWindowSize },
                            set: { store.scaleWithWindowSize = $0 }
                        ))
                    }
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                    .padding(.horizontal, 16)

                    Button {
                        store.resetToDefaults()
                        fontSize = store.fontSize
                        scale = store.scale
                        isBold = store.isBold
                        isItalic = store.isItalic
                        verticalPosition = store.verticalPosition
                        horizontalMargin = store.horizontalMargin
                        textBlur = store.textBlur
                        alignment = store.horizontalAlignment
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                    }
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 32)
                }
                .padding(.top, 8)
            }
            .background(MoonlitTheme.background)
            .navigationTitle("Subtitle Appearance")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var subtitlePreviewPanel: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard)
                .fill(Color.black)
                .overlay(
                    Image(systemName: "play.rectangle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60)
                        .foregroundColor(Color.white.opacity(0.08))
                )
                .frame(height: 120)

            Text("The quick brown fox jumps over the lazy dog")
                .font(.system(
                    size: min(fontSize * 0.45, 18),
                    weight: isBold ? .bold : .regular
                ))
                .italic(isItalic)
                .foregroundColor(Color(hex: store.textColorHex) ?? .white)
                .multilineTextAlignment(textAlignmentValue)
                .shadow(color: Color(hex: store.outlineColorHex) ?? .black, radius: 2, x: 1, y: 1)
                .blur(radius: textBlur * 0.3)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var textAlignmentValue: TextAlignment {
        switch alignment {
        case .left:   return .leading
        case .center: return .center
        case .right:  return .trailing
        }
    }

    private var alignmentRow: some View {
        HStack {
            Text("Horizontal Alignment")
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: Binding(
                get: { alignment },
                set: { alignment = $0; store.horizontalAlignment = $0 }
            )) {
                Text("Left").tag(SubtitleAlignment.left)
                Text("Center").tag(SubtitleAlignment.center)
                Text("Right").tag(SubtitleAlignment.right)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(MoonlitTheme.textTertiary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MoonlitTheme.accent)
            }
#if os(iOS)
            Slider(value: value, in: range, step: step)
                .tint(MoonlitTheme.accent)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
#endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func colorRow(_ title: String, hex: String, onChange: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Circle()
                .fill(Color(hex: hex) ?? .white)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            Text(hex)
                .font(.caption.monospaced())
                .foregroundColor(MoonlitTheme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(MoonlitTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func applyPreset(_ preset: SubtitlePreset) {
        store.preset = preset
        switch preset {
        case .standard:
            store.textColorHex = "#FFFFFF"
            store.outlineColorHex = "#000000"
            store.backgroundColorHex = "#000000"
            store.backgroundOpacity = 0.0
            store.isBold = false
        case .boxed:
            store.textColorHex = "#FFFFFF"
            store.outlineColorHex = "#000000"
            store.backgroundColorHex = "#000000"
            store.backgroundOpacity = 0.75
            store.isBold = false
        case .classic:
            store.textColorHex = "#FFFF00"
            store.outlineColorHex = "#000000"
            store.backgroundColorHex = "#000000"
            store.backgroundOpacity = 0.0
            store.isBold = false
        case .minimal:
            store.textColorHex = "#FFFFFF"
            store.outlineColorHex = "#000000"
            store.backgroundColorHex = "#000000"
            store.backgroundOpacity = 0.0
            store.isBold = false
        }
        isBold = store.isBold
    }
}

private extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let intVal = UInt64(h, radix: 16) else { return nil }
        let r = Double((intVal >> 16) & 0xFF) / 255
        let g = Double((intVal >> 8) & 0xFF) / 255
        let b = Double(intVal & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
