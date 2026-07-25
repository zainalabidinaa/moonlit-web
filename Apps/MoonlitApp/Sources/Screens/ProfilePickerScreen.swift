import SwiftUI
import MoonlitCore

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
            MoonlitTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("AppIconPreview")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(MoonlitTheme.radiusLarge)
                    .shadow(color: .black.opacity(0.35), radius: 20)

                Text("Who's watching?")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Text("Choose a profile")
                    .font(.subheadline)
                    .foregroundColor(MoonlitTheme.textSecondary)
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
                                        ? .white : MoonlitTheme.textSecondary)
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
                            .foregroundColor(MoonlitTheme.accent)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard, interactive: true)
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
    private func profileAvatarView(profile: MoonlitProfile, size: CGFloat) -> some View {
        if let avatarId = profile.avatarId,
           avatarId >= 0,
           avatarId < moonlitAvatarURLs.count,
           let url = URL(string: moonlitAvatarURLs[avatarId]) {
            let ext = url.pathExtension.lowercased()
            if ext == "gif" {
                AnimatedRemoteImage(url: url, contentMode: .scaleAspectFill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .glassCard(cornerRadius: size / 2, interactive: true)
            } else {
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
            }
        } else {
            fallbackAvatar(profile: profile, size: size)
        }
    }

    @ViewBuilder
    private func fallbackAvatar(profile: MoonlitProfile, size: CGFloat) -> some View {
        let color = profile.avatarColor.map { Color(hex: $0) } ?? MoonlitTheme.accent
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
                    .glassCard(cornerRadius: MoonlitTheme.radiusCard)
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
                            LottieLoadingView(size: 22)
                        }
                        Text("Create")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .glassProminentButtonStyle(tint: MoonlitTheme.accent, cornerRadius: MoonlitTheme.radiusCard)
                .disabled(name.isEmpty || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .background(MoonlitTheme.background)
            .navigationTitle("New Profile")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
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
    @State private var editingProfile: MoonlitProfile?

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()

                if profileManager.profiles.isEmpty {
                    Text("No profiles yet")
                        .foregroundColor(MoonlitTheme.textSecondary)
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
                                                .foregroundColor(MoonlitTheme.accent)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(MoonlitTheme.textTertiary)
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
#if os(iOS)
                    .scrollContentBackground(.hidden)
#endif
                }
            }
            .navigationTitle("Manage Profiles")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
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
    private func profileRowAvatar(profile: MoonlitProfile) -> some View {
        if let avatarId = profile.avatarId,
           avatarId >= 0,
           avatarId < moonlitAvatarURLs.count,
           let url = URL(string: moonlitAvatarURLs[avatarId]) {
            let ext = url.pathExtension.lowercased()
            if ext == "gif" {
                AnimatedRemoteImage(url: url, contentMode: .scaleAspectFill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
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
            }
        } else {
            fallbackRowAvatar(profile: profile)
        }
    }

    private func fallbackRowAvatar(profile: MoonlitProfile) -> some View {
        let color = profile.avatarColor.map { Color(hex: $0) } ?? MoonlitTheme.accent
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

    let profile: MoonlitProfile

    @State private var name: String
    @State private var selectedAvatarId: Int?
    @State private var isLoading = false
    @State private var gifStill: Bool

    init(profile: MoonlitProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _selectedAvatarId = State(initialValue: profile.avatarId)
        _gifStill = State(initialValue: UserDefaults.standard.bool(forKey: "avatar_gif_still_\(profile.id)"))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        currentAvatarPreview
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(MoonlitTheme.textSecondary)
                                .padding(.leading, 4)

                            TextField("Profile name", text: $name)
                                .padding()
                                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)

                        // Avatar picker — categorized horizontal scroll sections
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose a Picture")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(MoonlitTheme.textSecondary)
                                .padding(.leading, 20)

                            ForEach(moonlitAvatarCategories) { category in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 5) {
                                        Text(category.emoji)
                                            .font(.caption)
                                        Text(category.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(MoonlitTheme.textTertiary)
                                    }
                                    .padding(.leading, 20)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(category.indices, id: \.self) { index in
                                                avatarOptionTile(index: index)
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 4)
                                    }
                                }
                            }

                            // "No Avatar" option — falls back to profile initial
                            Button {
                                selectedAvatarId = nil
                            } label: {
                                VStack(spacing: 4) {
                                    Image("AppIconPreview")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(MoonlitTheme.radiusControl)
                                    Text("App Icon")
                                        .font(.caption2)
                                        .foregroundColor(MoonlitTheme.textSecondary)
                                }
                                .frame(width: 72, height: 72)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                                        .stroke(selectedAvatarId == nil ? MoonlitTheme.accent : Color.clear, lineWidth: 2.5)
                                )
                                .overlay(
                                    Group {
                                        if selectedAvatarId == nil {
                                            VStack {
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(MoonlitTheme.accent)
                                                        .font(.caption)
                                                        .padding(3)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 20)
                        }

                        // GIF toggle — only shown when selected avatar is animated
                        if let id = selectedAvatarId,
                           id < moonlitAvatarURLs.count,
                           moonlitAvatarURLs[id].hasSuffix(".gif") {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use Still Frame")
                                        .foregroundColor(.white)
                                    Text("Show a static image instead of animating")
                                        .font(.caption)
                                        .foregroundColor(MoonlitTheme.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $gifStill)
                                    .labelsHidden()
                                    .tint(MoonlitTheme.accent)
                            }
                            .padding()
                            .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                            .padding(.horizontal)
                        }

                        Button {
                            save()
                        } label: {
                            HStack {
                                if isLoading {
                                    LottieLoadingView(size: 22)
                                }
                                Text("Save")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .glassProminentButtonStyle(tint: MoonlitTheme.accent, cornerRadius: MoonlitTheme.radiusCard)
                        .disabled(name.isEmpty || isLoading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Edit Profile")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func avatarOptionTile(index: Int) -> some View {
        let urlString = moonlitAvatarURLs[index]
        let isSelected = selectedAvatarId == index
        Button {
            selectedAvatarId = index
        } label: {
            Group {
                if urlString.hasSuffix(".gif") {
                    if let url = URL(string: urlString) {
                        AnimatedRemoteImage(url: url, contentMode: .scaleAspectFill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                    }
                } else {
                    AsyncImage(url: URL(string: urlString)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                    .stroke(isSelected ? MoonlitTheme.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(
                Group {
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(MoonlitTheme.accent)
                                    .font(.caption)
                                    .padding(3)
                            }
                            Spacer()
                        }
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var currentAvatarPreview: some View {
        Group {
            if let avatarId = selectedAvatarId,
               avatarId >= 0,
               avatarId < moonlitAvatarURLs.count,
               let url = URL(string: moonlitAvatarURLs[avatarId]) {
                let ext = url.pathExtension.lowercased()
                if ext == "gif" {
                    AnimatedRemoteImage(url: url, contentMode: .scaleAspectFill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
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
                }
            } else {
                avatarInitialCircle
            }
        }
    }

    private var avatarInitialCircle: some View {
        let color = profile.avatarColor.map { Color(hex: $0) } ?? MoonlitTheme.accent
        return Circle()
            .fill(color)
            .frame(width: 80, height: 80)
            .overlay(
                Text(String(name.prefix(1).uppercased()))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private func save() {
        Task {
            isLoading = true
            let updated = MoonlitProfile(
                id: profile.id,
                userId: profile.userId,
                name: name,
                avatarColor: profile.avatarColor,
                avatarId: selectedAvatarId,
                profileIndex: profile.profileIndex,
                usesPrimaryAddons: profile.usesPrimaryAddons,
                pinEnabled: profile.pinEnabled,
                role: profile.role,
                createdAt: profile.createdAt
            )
            try? await profileManager.updateProfile(updated)
            UserDefaults.standard.set(gifStill, forKey: "avatar_gif_still_\(profile.id)")
            isLoading = false
            dismiss()
        }
    }
}
