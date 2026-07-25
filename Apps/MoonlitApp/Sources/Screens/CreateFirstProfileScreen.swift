import SwiftUI
import MoonlitCore

private let gold = Color(hex: "#C8941A")

private let profileEmojis: [String] = ["🌙", "⭐", "🎬", "🍿", "🦊", "🐉", "👾", "🌊", "🔮", "⚡"]

struct CreateFirstProfileScreen: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var name = ""
    @State private var selectedEmoji = "🌙"
    @State private var showEmojiGrid = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SplashStarField().ignoresSafeArea()

            RadialGradient(
                colors: [gold.opacity(0.06), .clear],
                center: .init(x: 0.5, y: 0.18),
                startRadius: 0, endRadius: 220
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // Eyebrow + titles
                    Text("ALMOST THERE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(gold.opacity(0.65))
                        .kerning(4)
                        .padding(.bottom, 10)

                    Text("Create Your Profile")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 4)

                    Text("Who's watching?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.bottom, 28)

                    // Icon ring
                    VStack(spacing: 8) {
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { showEmojiGrid.toggle() }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(
                                        gold.opacity(0.38),
                                        style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                                    )
                                    .frame(width: 88, height: 88)

                                Text(selectedEmoji)
                                    .font(.system(size: 38))

                                // + badge
                                Circle()
                                    .fill(gold.opacity(0.9))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Color.black)
                                    )
                                    .offset(x: 30, y: 30)
                            }
                        }
                        .buttonStyle(.plain)

                        Text("Tap to choose an icon")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(gold.opacity(0.6))
                    }
                    .padding(.bottom, 20)

                    // Emoji grid
                    if showEmojiGrid {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                            ForEach(profileEmojis, id: \.self) { emoji in
                                Button {
                                    withAnimation(.smooth(duration: 0.2)) { selectedEmoji = emoji }
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 24))
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(1, contentMode: .fill)
                                        .background(
                                            selectedEmoji == emoji
                                                ? gold.opacity(0.18)
                                                : Color.white.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                                                .stroke(
                                                    selectedEmoji == emoji
                                                        ? gold.opacity(0.45)
                                                        : Color.white.opacity(0.06),
                                                    lineWidth: 1.5
                                                )
                                        )
                                        .scaleEffect(selectedEmoji == emoji ? 1.06 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .animation(.smooth(duration: 0.18), value: selectedEmoji)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR NAME")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .kerning(1)

                        TextField("e.g. Zain", text: $name)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                                    .stroke(.white.opacity(0.09), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)

                    // Error
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 28)
                            .padding(.bottom, 4)
                    }

                    Spacer().frame(height: 28)

                    // Create button
                    Button(action: create) {
                        HStack(spacing: 8) {
                            if isLoading { LottieLoadingView(size: 20) }
                            Text("Create Profile")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                    }
                    .goldProfileCTA()
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.45)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 52)
                }
            }
            .scrollIndicators(.hidden)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.5).delay(0.1)) { appeared = true }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                // Store emoji as avatarColor with "emoji:" prefix so ProfileAvatarView
                // can detect and render it in the future. For now it falls back to initials.
                try await profileManager.createProfile(name: trimmed)
                profileManager.currentProfile = profileManager.profiles.first
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// Button style scoped to this file
private extension View {
    func goldProfileCTA() -> some View {
        self
            .foregroundStyle(gold)
            .background(gold.opacity(0.12), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                    .stroke(gold.opacity(0.32), lineWidth: 1)
            )
    }
}
