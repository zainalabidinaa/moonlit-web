import SwiftUI
import LunaCore

struct ContentView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared

    var body: some View {
        Group {
            if profileManager.isAuthenticated {
                if profileManager.currentProfile != nil {
                    MainTabView()
                } else if !profileManager.profiles.isEmpty {
                    ProfilePickerScreen()
                } else {
                    CreateFirstProfileScreen()
                }
            } else {
                AuthScreen()
            }
        }
        .onChange(of: profileManager.currentProfile) { _, profile in
            roleManager.evaluateRole(profile: profile)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared

    @State private var selectedTab = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(selection: $selectedTab) {
                    Label("Home", systemImage: "house.fill").tag(0)
                    Label("Search", systemImage: "magnifyingglass").tag(1)
                    Label("Library", systemImage: "bookmark.fill").tag(2)
                    Label("Settings", systemImage: "gearshape.fill").tag(3)
                    if roleManager.isAdmin {
                        Label("Admin", systemImage: "shield.fill").tag(4)
                    }
                }
                .listStyle(.sidebar)
            } detail: {
                tabContent
            }
            .task {
                if let profile = profileManager.currentProfile {
                    await addonRepo.loadAddons(profileId: profile.id)
                }
            }
            .onChange(of: profileManager.currentProfile) { _, newProfile in
                if let profile = newProfile {
                    Task {
                        await addonRepo.loadAddons(profileId: profile.id)
                    }
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                tabContent
                    .accentColor(.purple)
            }
            .task {
                if let profile = profileManager.currentProfile {
                    await addonRepo.loadAddons(profileId: profile.id)
                }
            }
            .onChange(of: profileManager.currentProfile) { _, newProfile in
                if let profile = newProfile {
                    Task {
                        await addonRepo.loadAddons(profileId: profile.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if sizeClass == .regular {
            switch selectedTab {
            case 0: HomeScreen()
            case 1: SearchScreen()
            case 2: LibraryScreen()
            case 3: SettingsScreen()
            case 4: AdminDashboard()
            default: HomeScreen()
            }
        } else {
            Group {
                HomeScreen()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)

                SearchScreen()
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .tag(1)

                LibraryScreen()
                    .tabItem {
                        Image(systemName: "bookmark.fill")
                        Text("Library")
                    }
                    .tag(2)

                SettingsScreen()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .tag(3)

                if roleManager.isAdmin {
                    AdminDashboard()
                        .tabItem {
                            Image(systemName: "shield.fill")
                            Text("Admin")
                        }
                        .tag(4)
                }
            }
        }
    }
}
