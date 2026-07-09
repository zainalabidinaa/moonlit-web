import SwiftUI
import MoonlitCore

enum MacMainTab: String, CaseIterable {
    case home, movies, series, library, downloads, settings, admin

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film.fill"
        case .series: return "tv.fill"
        case .library: return "rectangle.stack.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gear"
        case .admin: return "shield.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .series: return "Series"
        case .library: return "Library"
        case .downloads: return "Downloads"
        case .settings: return "Settings"
        case .admin: return "Admin"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .movies: return "2"
        case .series: return "3"
        case .library: return "4"
        case .downloads: return "5"
        case .settings: return "6"
        case .admin: return "7"
        }
    }
}

/// Invisible nav bar — text floating directly over the hero with no background.
/// Active tab gets a clean white underline. Pure content-first approach.

struct PillNavBar: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @Binding var selectedTab: MacMainTab
    var onSearchTapped: () -> Void = {}

    @State private var isAccountMenuPresented = false
    @State private var isSearchHovering = false

    private var visibleTabs: [MacMainTab] {
        [.home, .movies, .series, .library]
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("MOONLIT")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.white)
                .tracking(2)
                .padding(.leading, 20)
                .padding(.trailing, 12)

            HStack(spacing: 2) {
                ForEach(visibleTabs, id: \.self) { tab in
                    tabButton(tab)
                }
            }

            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedTab = .downloads }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(selectedTab == .downloads ? .white : .white.opacity(0.6))
                        .padding(6)
                        .background(selectedTab == .downloads ? Color.white.opacity(0.10) : .clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Downloads")
                .keyboardShortcut(MacMainTab.downloads.keyboardShortcut, modifiers: .command)

                searchField
                accountButton
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .macLiquidGlassCapsule(interactive: true)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSearchHovering)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(isSearchHovering ? 0.9 : 0.55))

            if isSearchHovering {
                Text("Search")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
        .padding(.horizontal, isSearchHovering ? 14 : 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(isSearchHovering ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isSearchHovering = hovering
            }
        }
        .onTapGesture {
            onSearchTapped()
        }
    }

    private func tabButton(_ tab: MacMainTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.label)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                .fixedSize()
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.10))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
    }

    private var accountButton: some View {
        Button {
            isAccountMenuPresented = true
        } label: {
            MacProfileAvatarView(
                avatarId: profileManager.currentProfile?.avatarId,
                name: profileManager.currentProfile?.name ?? "?",
                avatarColor: profileManager.currentProfile?.avatarColor,
                size: 30
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .popover(isPresented: $isAccountMenuPresented, arrowEdge: .top) {
            accountMenuContent
        }
    }

    private var accountMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let profile = profileManager.currentProfile {
                Text(profile.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MoonlitTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                Divider()
            }

            accountMenuRow(title: "Settings", icon: "gear") {
                isAccountMenuPresented = false
                selectedTab = .settings
            }
            accountMenuRow(title: "Switch Profile", icon: "person.2") {
                isAccountMenuPresented = false
                profileManager.currentProfile = nil
            }
            accountMenuRow(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right", tint: .red) {
                isAccountMenuPresented = false
                profileManager.currentProfile = nil
                Task { await profileManager.signOut() }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
        .background(MoonlitTheme.surfaceElevated)
    }

    private func accountMenuRow(title: String, icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
