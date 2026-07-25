#if os(iOS)
import SwiftUI
import UIKit
import MoonlitCore

enum AppIconStyle: String {
    case clapperboard
}

@MainActor
enum AppIconManager {
    static let storageKey = "moonlit.appIconStyle"

    static var selectedStyle: AppIconStyle {
        get {
            AppIconStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .clapperboard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    static func iconName(for style: AppIconStyle, colorScheme _: ColorScheme) -> String? {
        switch style {
        case .clapperboard:
            return nil
        }
    }

    static func applySelectedIcon(for colorScheme: ColorScheme, completion: ((Error?) -> Void)? = nil) {
        apply(style: selectedStyle, colorScheme: colorScheme, persist: false, completion: completion)
    }

    static func apply(style: AppIconStyle, colorScheme: ColorScheme, persist: Bool = true, completion: ((Error?) -> Void)? = nil) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion?(nil)
            return
        }

        let iconName = iconName(for: style, colorScheme: colorScheme)
        guard UIApplication.shared.alternateIconName != iconName else {
            if persist {
                selectedStyle = style
            }
            completion?(nil)
            return
        }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            DispatchQueue.main.async {
                if error == nil, persist {
                    selectedStyle = style
                }
                completion?(error)
            }
        }
    }
}

struct AppIconOption: Identifiable {
    let id: AppIconStyle
    let name: String
    let assetName: String
}

private let iconOptions: [AppIconOption] = [
    AppIconOption(id: .clapperboard, name: "Clapperboard", assetName: "AppIconPreview"),
]

struct AppIconPickerScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentStyle = AppIconManager.selectedStyle
    @State private var isChanging = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(iconOptions) { option in
                        iconCell(option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .background(MoonlitTheme.background)
        .navigationTitle("App Icon")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder
    private func iconCell(_ option: AppIconOption) -> some View {
        let isSelected = currentStyle == option.id

        Button {
            guard !isChanging, !isSelected else { return }
            applyIcon(option)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    // Preview from asset catalog (1024px icon)
                    Image(option.assetName)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(1, contentMode: .fit)
                        .cornerRadius(MoonlitTheme.radiusLarge)
                        .overlay(
                            RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge)
                                .strokeBorder(
                                    isSelected ? MoonlitTheme.accent : Color.clear,
                                    lineWidth: 3
                                )
                        )
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(MoonlitTheme.accent)
                                    .background(Circle().fill(Color.black).padding(2))
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }

                Text(option.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? MoonlitTheme.accent : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .opacity(isChanging ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func applyIcon(_ option: AppIconOption) {
        isChanging = true
        errorMessage = nil
        AppIconManager.apply(style: option.id, colorScheme: colorScheme) { error in
            isChanging = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                currentStyle = option.id
            }
        }
    }
}
#endif
