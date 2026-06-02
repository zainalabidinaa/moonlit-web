import SwiftUI
import LunaCore

private let defaultAvatarURLs: [String] = [
    "https://media1.tenor.com/m/BbkxgHGg-EEAAAAC/butcher-billy-butcher.gif",
    "https://i.pinimg.com/originals/29/bd/26/29bd261d201e956588ee777d37d26800.gif",
    "https://i.postimg.cc/cLnhTxnr/Rick-Grimes-v2.png",
    "https://media1.giphy.com/media/v1.Y2lkPTZjMDliOTUycDg5cGFzNm1ydWo2aGZ2Njl4NnZiOHpvdjdsbHdzaTBmcTk2bGZnYyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/1qErVv5GVUac8uqBJU/giphy.gif",
    "https://media1.tenor.com/m/ZNyte-qzI8QAAAAC/spider-man-drink.gif"
]

struct ProfilePickerScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreateProfile = false
    @State private var showManageProfiles = false

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
                                profileAvatarView(profile: profile, size: 88)

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
                    showManageProfiles = true
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
            ProfileCreateSheet()
        }
        .sheet(isPresented: $showManageProfiles) {
            ManageProfilesSheet()
        }
    }

    @ViewBuilder
    private func profileAvatarView(profile: LunaProfile, size: CGFloat) -> some View {
        if let avatarId = profile.avatarId,
           avatarId >= 0,
           avatarId < defaultAvatarURLs.count,
           let url = URL(string: defaultAvatarURLs[avatarId]) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .glassCard(cornerRadius: size / 2, interactive: true)
                case .failure, .empty:
                    fallbackAvatar(profile: profile, size: size)
                @unknown default:
                    fallbackAvatar(profile: profile, size: size)
                }
            }
        } else {
            fallbackAvatar(profile: profile, size: size)
        }
    }

    @ViewBuilder
    private func fallbackAvatar(profile: LunaProfile, size: CGFloat) -> some View {
        let color = profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(String(profile.name.prefix(1).uppercased()))
                    .font(.system(size: size * 0.41, weight: .bold))
                    .foregroundColor(.white)
            )
            .glassCard(cornerRadius: size / 2, interactive: true)
            .shadow(color: color.opacity(0.3), radius: 16)
    }
}

struct ProfileCreateSheet: View {
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

struct ManageProfilesSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile: LunaProfile?

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                if profileManager.profiles.isEmpty {
                    Text("No profiles yet")
                        .foregroundColor(LunaTheme.textSecondary)
                } else {
                    List {
                        ForEach(profileManager.profiles) { profile in
                            Button {
                                editingProfile = profile
                            } label: {
                                HStack(spacing: 12) {
                                    profileRowAvatar(profile: profile)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.white)

                                        if profile.id == profileManager.currentProfile?.id {
                                            Text("Current")
                                                .font(.caption)
                                                .foregroundColor(LunaTheme.accent)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(LunaTheme.textTertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                let profile = profileManager.profiles[idx]
                                Task {
                                    try? await profileManager.deleteProfile(profile)
                                }
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Manage Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingProfile) { profile in
            EditProfileSheet(profile: profile)
        }
    }

    @ViewBuilder
    private func profileRowAvatar(profile: LunaProfile) -> some View {
        if let avatarId = profile.avatarId,
           avatarId >= 0,
           avatarId < defaultAvatarURLs.count,
           let url = URL(string: defaultAvatarURLs[avatarId]) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                case .failure, .empty:
                    fallbackRowAvatar(profile: profile)
                @unknown default:
                    fallbackRowAvatar(profile: profile)
                }
            }
        } else {
            fallbackRowAvatar(profile: profile)
        }
    }

    private func fallbackRowAvatar(profile: LunaProfile) -> some View {
        let color = profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent
        return Circle()
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                Text(String(profile.name.prefix(1).uppercased()))
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
            )
    }
}

struct EditProfileSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    let profile: LunaProfile

    @State private var name: String
    @State private var selectedAvatarId: Int?
    @State private var isLoading = false

    init(profile: LunaProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _selectedAvatarId = State(initialValue: profile.avatarId)
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        currentAvatarPreview
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(LunaTheme.textSecondary)
                                .padding(.leading, 4)

                            TextField("Profile name", text: $name)
                                .padding()
                                .glassCard(cornerRadius: 12)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose a Picture")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(LunaTheme.textSecondary)
                                .padding(.leading, 4)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Array(defaultAvatarURLs.enumerated()), id: \.offset) { index, urlString in
                                    Button {
                                        selectedAvatarId = index
                                    } label: {
                                        AsyncImage(url: URL(string: urlString)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 88, height: 88)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                            case .failure, .empty:
                                                fallbackAvatarOption(label: "?")
                                            @unknown default:
                                                fallbackAvatarOption(label: "?")
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    selectedAvatarId == index
                                                        ? LunaTheme.accent
                                                        : Color.clear,
                                                    lineWidth: 3
                                                )
                                        )
                                        .overlay(
                                            Group {
                                                if selectedAvatarId == index {
                                                    VStack {
                                                        HStack {
                                                            Spacer()
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .foregroundColor(LunaTheme.accent)
                                                                .font(.title3)
                                                                .padding(4)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    selectedAvatarId = nil
                                } label: {
                                    VStack(spacing: 4) {
                                        Image("luna-icon")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 36, height: 36)
                                            .cornerRadius(8)
                                        Text("App Icon")
                                            .font(.caption2)
                                            .foregroundColor(LunaTheme.textSecondary)
                                    }
                                    .frame(width: 88, height: 88)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedAvatarId == nil
                                                    ? LunaTheme.accent
                                                    : Color.clear,
                                                lineWidth: 3
                                            )
                                    )
                                    .overlay(
                                        Group {
                                            if selectedAvatarId == nil {
                                                VStack {
                                                    HStack {
                                                        Spacer()
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundColor(LunaTheme.accent)
                                                            .font(.title3)
                                                            .padding(4)
                                                    }
                                                    Spacer()
                                                }
                                            }
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)

                        Button {
                            save()
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text("Save")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .glassProminentButtonStyle(tint: LunaTheme.accent, cornerRadius: 12)
                        .disabled(name.isEmpty || isLoading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var currentAvatarPreview: some View {
        Group {
            if let avatarId = selectedAvatarId,
               avatarId >= 0,
               avatarId < defaultAvatarURLs.count,
               let url = URL(string: defaultAvatarURLs[avatarId]) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    case .failure, .empty:
                        avatarInitialCircle
                    @unknown default:
                        avatarInitialCircle
                    }
                }
            } else {
                avatarInitialCircle
            }
        }
    }

    private var avatarInitialCircle: some View {
        let color = profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent
        return Circle()
            .fill(color)
            .frame(width: 80, height: 80)
            .overlay(
                Text(String(name.prefix(1).uppercased()))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    @ViewBuilder
    private func fallbackAvatarOption(label: String) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 88, height: 88)
            .overlay(
                Text(label)
                    .font(.caption)
                    .foregroundColor(LunaTheme.textTertiary)
            )
    }

    private func save() {
        Task {
            isLoading = true
            var updated = profile
            updated = LunaProfile(
                id: updated.id,
                userId: updated.userId,
                name: name,
                avatarColor: updated.avatarColor,
                avatarId: selectedAvatarId,
                profileIndex: updated.profileIndex,
                usesPrimaryAddons: updated.usesPrimaryAddons,
                pinEnabled: updated.pinEnabled,
                role: updated.role,
                createdAt: updated.createdAt
            )
            try? await profileManager.updateProfile(updated)
            isLoading = false
            dismiss()
        }
    }
}
