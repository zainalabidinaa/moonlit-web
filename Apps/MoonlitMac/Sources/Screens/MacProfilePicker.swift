import SwiftUI
import MoonlitCore

struct MacProfilePicker: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreate = false

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            VStack(spacing: 28) {
                Spacer()

                AppIconView()
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.35), radius: 16)

                Text("Who's watching?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120))],
                    spacing: 20
                ) {
                    ForEach(profileManager.profiles) { profile in
                        Button {
                            profileManager.selectProfile(profile)
                        } label: {
                            VStack(spacing: 8) {
                                MacProfileAvatarView(
                                    avatarId: profile.avatarId,
                                    name: profile.name,
                                    avatarColor: profile.avatarColor,
                                    size: 80
                                )
                                Text(profile.name)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                if profile.isAdmin {
                                    Text("Admin")
                                        .font(.caption2)
                                        .foregroundColor(MoonlitTheme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showCreate = true } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                )
                            Text("Add Profile")
                                .font(.subheadline)
                                .foregroundColor(MoonlitTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 500)

                Button("Sign Out") {
                    Task { await profileManager.signOut() }
                }
                .foregroundColor(MoonlitTheme.textTertiary)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showCreate) {
                MacCreateProfile()
            }
        }
        .background(MoonlitTheme.background)
    }
}

struct MacCreateProfile: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAvatarId = Int.random(in: 0..<moonlitAvatarURLs.count)

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            AppIconView()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.35), radius: 20)

            Text("Create Profile")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            MacProfileAvatarView(
                avatarId: selectedAvatarId,
                name: name.isEmpty ? "?" : name,
                avatarColor: nil,
                size: 92
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(0..<moonlitAvatarURLs.count, id: \.self) { index in
                        Button {
                            selectedAvatarId = index
                        } label: {
                            MacProfileAvatarView(avatarId: index, name: "", avatarColor: nil, size: 54)
                                .overlay(
                                    Circle().strokeBorder(
                                        selectedAvatarId == index ? MoonlitTheme.ratingGold : Color.clear,
                                        lineWidth: 3
                                    )
                                )
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(width: 340, height: 180)

            TextField("Profile Name", text: $name)
                .textFieldStyle(.plain)
                .padding(10)
                .background(MoonlitTheme.surface)
                .cornerRadius(MoonlitTheme.radiusControl)
                .overlay(
                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 300)
                .foregroundColor(.white)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button {
                createProfile()
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        MacStrokeSpinner(size: 18, color: .black)
                    }
                    Text("Create Profile")
                        .fontWeight(.semibold)
                }
                .frame(width: 300, height: 40)
            }
            .buttonStyle(MoonlitPrimaryButtonStyle(cornerRadius: 20))
            .disabled(name.isEmpty || isLoading)

            Spacer()
        }
        .frame(width: 420, height: 600)
        .background(MoonlitTheme.background)
    }

    private func createProfile() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await profileManager.createProfile(name: name, avatarId: selectedAvatarId)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
