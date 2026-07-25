import SwiftUI
import MoonlitCore

@main
struct MoonlitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var roleManager = RoleManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        MoonlitTypography.registerFonts()
        // Seed the poster-badge defaults (Genre + Rating + Trend on) so PosterService's
        // non-isolated UserDefaults reads match the @AppStorage defaults on a fresh install.
        PosterService.registerDefaults()
        // Don't install a custom UITabBarAppearance — on iOS 26 that opts the tab bar out
        // of the system's clear Liquid Glass. Leave it default; tint/unselected colors are
        // driven by SwiftUI (.tint) on the TabView.
        UITabBar.appearance().tintColor = .systemBlue
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.55)

        // Quiesce UIKit-backed animations under UI automation so XCUITest can sync.
        if UITestMode.disableContinuousAnimations {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            // TEMP: paywall design prototype, launch with -PAYWALL_PREVIEW YES.
            // Remove once the paywall design is finalized.
            if ProcessInfo.processInfo.arguments.contains("PAYWALL_PREVIEW") {
                PaywallScreen(posterURLs: (0..<12).compactMap {
                    URL(string: "https://picsum.photos/seed/moonlit\($0)/300/450")
                })
            } else {
                MoonlitRootView(handleDeepLink: handleDeepLink)
                    .environmentObject(profileManager)
                    .environmentObject(roleManager)
                    .environmentObject(themeManager)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme else { return }

        if scheme == "moonlit",
           url.host == "install-addon",
           let addonURL = URLComponents(url: url, resolvingAgainstBaseURL: true)?
               .queryItems?.first(where: { $0.name == "url" })?.value {
            Task {
                await AddonRepository.shared.installAddon(url: addonURL)
                ToastPresenter.shared.show(message: "Addon installed", style: .success)
            }
        }
    }
}

private struct MoonlitRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    let handleDeepLink: (URL) -> Void

    var body: some View {
        ContentView()
            .preferredColorScheme(.dark)
            .tint(.blue)
            .accentColor(.blue)
            .onOpenURL { handleDeepLink($0) }
            .task {
                AppIconManager.applySelectedIcon(for: colorScheme)
            }
            .onChange(of: colorScheme) { _, newValue in
                AppIconManager.applySelectedIcon(for: newValue)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, let userId = profileManager.currentProfile?.userId {
                    Task {
                        try? await profileManager.loadProfiles(userId: userId)
                        if let profile = profileManager.currentProfile {
                            roleManager.evaluateRole(profile: profile)
                        }
                    }
                }
            }
    }
}
