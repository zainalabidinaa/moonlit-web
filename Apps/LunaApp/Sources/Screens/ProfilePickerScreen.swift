import SwiftUI
import LunaCore

struct ProfilePickerScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreateProfile = false

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ZStack {
            LunaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("luna-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(18)
                    .shadow(color: LunaTheme.accent.opacity(0.4), radius: 20)

                Text("Who's watching?")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Text("Choose a profile")
                    .font(.subheadline)
                    .foregroundColor(LunaTheme.textSecondary)
                    .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(profileManager.profiles) { profile in
                        Button {
                            profileManager.currentProfile = profile
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(
                                        profile.avatarColor.map { Color(hex: $0) }
                                        ?? LunaTheme.accent
                                    )
                                    .frame(width: 88, height: 88)
                                    .overlay(
                                        Text(String(profile.name.prefix(1).uppercased()))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                    .glassCard(cornerRadius: 44, interactive: true)
                                    .shadow(
                                        color: (profile.avatarColor.map { Color(hex: $0) }
                                            ?? LunaTheme.accent).opacity(0.3),
                                        radius: 16
                                    )

                                Text(profile.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(profile.id == profileManager.currentProfile?.id
                                        ? .white : LunaTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showCreateProfile = true
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                                .frame(width: 88, height: 88)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(LunaTheme.textTertiary)
                                )

                            Text("Add Profile")
                                .font(.subheadline)
                                .foregroundColor(LunaTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)

                Spacer()

                Button {
                    // Navigate to profile management
                } label: {
                    HStack {
                        Text("Manage Profiles")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Image(systemName: "gearshape")
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.accent)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 14, interactive: true)
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showCreateProfile) {
            CreateProfileSheet()
        }
    }
}

struct CreateProfileSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Create a new profile")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top)

                TextField("Profile name", text: $name)
                    .padding()
                    .glassCard(cornerRadius: 12)
                    .foregroundColor(.white)
                    .padding(.horizontal)

                Button {
                    Task {
                        isLoading = true
                        try? await profileManager.createProfile(name: name)
                        isLoading = false
                        dismiss()
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text("Create")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .glassProminentButtonStyle(tint: LunaTheme.accent, cornerRadius: 12)
                .disabled(name.isEmpty || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .background(LunaTheme.background)
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
