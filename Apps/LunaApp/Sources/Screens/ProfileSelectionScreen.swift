import SwiftUI
import LunaCore

struct ProfileSelectionScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreateProfile = false
    @State private var newProfileName = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            LunaTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 48))
                    .foregroundColor(LunaTheme.accent)

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
                                        .fill(profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
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
                                            .foregroundColor(LunaTheme.accent)
                                    }
                                }
                            }
                        }

                        Button { showCreateProfile = true } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .stroke(LunaTheme.textSecondary, lineWidth: 2)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(LunaTheme.textSecondary)
                                    )
                                Text("Add Profile")
                                    .font(.subheadline)
                                    .foregroundColor(LunaTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }

                Button(action: { Task { await profileManager.signOut() } }) {
                    Text("Sign Out")
                        .font(.subheadline)
                        .foregroundColor(LunaTheme.textSecondary)
                }

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

struct CreateFirstProfileScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var name = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            LunaTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundColor(LunaTheme.accent)

                Text("Create Your First Profile")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                TextField("Profile Name", text: $name)
                    .padding()
                    .background(LunaTheme.surface)
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)

                Button(action: {
                    isLoading = true
                    Task {
                        try await profileManager.createProfile(name: name)
                        isLoading = false
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text("Create Profile")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LunaTheme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(name.isEmpty || isLoading)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

struct CreateProfileSheet: View {
    @Binding var isPresented: Bool
    @Binding var profileName: String
    let onCreate: () async throws -> Void
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    TextField("Profile name", text: $profileName)
                        .padding()
                        .background(LunaTheme.surface)
                        .cornerRadius(12)
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
                            .background(LunaTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(profileName.isEmpty || isLoading)
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

