import SwiftUI
import LunaCore

enum MacMainTab: String, CaseIterable {
    case home, search, library, settings, admin

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "book.fill"
        case .settings: return "gear"
        case .admin: return "shield.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .settings: return "Settings"
        case .admin: return "Admin"
        }
    }
}

struct PillNavBar: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @Binding var selectedTab: MacMainTab

    private var visibleTabs: [MacMainTab] {
        var tabs: [MacMainTab] = [.home, .search, .library, .settings]
        if roleManager.isAdmin { tabs.append(.admin) }
        return tabs
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? Capsule().fill(Color.white.opacity(0.12))
                            : Capsule().fill(Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 8)

            // Profile button
            Button {
                profileManager.currentProfile = nil
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            profileManager.currentProfile?.avatarColor
                                .map { Color(hex: $0) } ?? LunaTheme.accent
                        )
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(profileManager.currentProfile?.name.prefix(1) ?? "?"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text(profileManager.currentProfile?.name ?? "Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            GlassMaterialView()
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
    }
}

struct GlassMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 999
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
