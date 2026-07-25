import SwiftUI
import MoonlitCore

struct ProfileSelectionScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreateProfile = false
    @State private var newProfileName = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            MoonlitTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 48))
                    .foregroundColor(MoonlitTheme.accent)

                Text("Who's watching?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                        ForEach(profileManager.profiles) { profile in
                            Button {
                                profileManager.selectProfile(profile)
                            } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(profile.avatarColor.map { Color(hex: $0) } ?? MoonlitTheme.accent)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Text(String(profile.name.prefix(1).uppercased()))
                                                .font(.title)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        )

                                    Text(profile.name)
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    if profile.isAdmin {
                                        Text("Admin")
                                            .font(.caption2)
                                            .foregroundColor(MoonlitTheme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            #if os(tvOS)
                            .tvosFocusScale()
                            #endif
                        }

                        Button { showCreateProfile = true } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .stroke(MoonlitTheme.textSecondary, lineWidth: 2)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(MoonlitTheme.textSecondary)
                                    )
                                Text("Add Profile")
                                    .font(.subheadline)
                                    .foregroundColor(MoonlitTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        #if os(tvOS)
                        .tvosFocusScale()
                        #endif
                    }
                    .padding(.horizontal, 32)
                }

                Button(action: { Task { await profileManager.signOut() } }) {
                    Text("Sign Out")
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)
                }
                .buttonStyle(.plain)
                #if os(tvOS)
                .tvosFocusScale()
                #endif

                Spacer()
            }
            .sheet(isPresented: $showCreateProfile) {
                CreateProfileSheet(
                    isPresented: $showCreateProfile,
                    profileName: $newProfileName,
                    onCreate: {
                        Task {
                            try await profileManager.createProfile(name: newProfileName)
                            newProfileName = ""
                        }
                    }
                )
            }
        }
    }
}

#if os(tvOS)
private struct TVFocusModifier: ViewModifier {
    @Environment(\.isFocused) var isFocused
    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}

private extension View {
    func tvosFocusScale() -> some View {
        modifier(TVFocusModifier())
    }
}
#endif

struct CreateProfileSheet: View {
    @Binding var isPresented: Bool
    @Binding var profileName: String
    let onCreate: () async throws -> Void
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    TextField("Profile name", text: $profileName)
                        .padding()
                        .background(MoonlitTheme.surface)
                        .cornerRadius(MoonlitTheme.radiusCard)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Button {
                        isLoading = true
                        Task {
                            try await onCreate()
                            isLoading = false
                            isPresented = false
                        }
                    } label: {
                        Text("Create")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(MoonlitTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(MoonlitTheme.radiusCard)
                    }
                    .disabled(profileName.isEmpty || isLoading)
                    .buttonStyle(.plain)
                    #if os(tvOS)
                    .tvosFocusScale()
                    #endif
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("New Profile")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        #if os(tvOS)
                        .tvosFocusScale()
                        #endif
                }
            }
        }
    }
}
