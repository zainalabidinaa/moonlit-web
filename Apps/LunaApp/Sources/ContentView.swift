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

    var body: some View {
        TabView(selection: $selectedTab) {
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
        .accentColor(.purple)
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
