import SwiftUI
import MoonlitCore

struct ContentView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @AppStorage("moonlit.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("moonlit.guestMode") private var guestMode = false

    var body: some View {
        Group {
            if !profileManager.hasRestoredSession {
                SessionRestoreView()
            } else if !hasSeenOnboarding {
                OnboardingView()
            } else if profileManager.isAuthenticated {
                if let profile = profileManager.currentProfile, profile.profileRole.isRestricted {
                    RestrictedAccessView()
                } else if profileManager.currentProfile != nil {
                    MainTabView()
                } else if !profileManager.profiles.isEmpty {
                    ProfilePickerScreen()
                } else {
                    CreateFirstProfileScreen()
                }
            } else if guestMode {
                MainTabView()
            } else {
                #if os(tvOS)
                TVAuthScreen()
                #else
                AuthScreen()
                #endif
            }
        }
        .onChange(of: profileManager.currentProfile) { _, profile in
            roleManager.evaluateRole(profile: profile)
        }
        .onChange(of: profileManager.hasRestoredSession) { _, restored in
            if restored, let profile = profileManager.currentProfile {
                roleManager.evaluateRole(profile: profile)
            }
        }
        .onAppear {
            if profileManager.hasRestoredSession, let profile = profileManager.currentProfile {
                roleManager.evaluateRole(profile: profile)
            }
        }
        .onOpenURL { url in
            TraktAuthService.shared.handleCallback(url: url)
        }
    }
}

private struct SessionRestoreView: View {
    @State private var iconScale: CGFloat = 0.86
    @State private var iconOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 8
    @State private var progressWidth: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#101114"), Color(hex: "#050506")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(hex: "#FF8A35").opacity(0.42),
                    Color(hex: "#FF8A35").opacity(0.14),
                    .clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 168
            )
            .frame(width: 320, height: 320)
            .blur(radius: 18)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FF8A35").opacity(0.32))
                        .frame(width: 176, height: 176)
                        .blur(radius: 34)

                    Image("AppIconPreview")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: Color(hex: "#FF8A35").opacity(0.34), radius: 34, y: 14)
                        .shadow(color: .black.opacity(0.52), radius: 28, y: 18)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                Text("Moonlit")
                    .font(.system(size: 40, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 112 * progressWidth)
                }
                .frame(width: 112, height: 4)
                .clipShape(Capsule())
                .padding(.top, 8)
                .opacity(wordmarkOpacity)
            }
            .offset(y: -8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.08)) {
                iconScale = 1
                iconOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.46).delay(0.34)) {
                wordmarkOpacity = 1
                wordmarkOffset = 0
            }
            withAnimation(.easeInOut(duration: 1.35).delay(0.55)) {
                progressWidth = 0.72
            }
        }
    }
}

// TimelineView + Canvas = single draw call per frame, no per-star view overhead
struct SplashStarField: View {
    struct Particle {
        let x: CGFloat      // normalized 0–1 horizontal
        let size: CGFloat   // diameter in points
        let opacity: Double // peak opacity
        let speed: CGFloat  // points per second (upward)
        let phase: CGFloat  // normalized 0–1 starting position in cycle
    }

    private let particles: [Particle] = (0..<38).map { _ in
        Particle(
            x:       .random(in: 0...1),
            size:    .random(in: 0.6...2.4),
            opacity: .random(in: 0.12...0.6),
            speed:   .random(in: 35...95),
            phase:   .random(in: 0...1)
        )
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let now  = CGFloat(tl.date.timeIntervalSinceReferenceDate)
                let cycH = size.height + 20

                for p in particles {
                    let traveled = (now * p.speed + p.phase * cycH)
                        .truncatingRemainder(dividingBy: cycH)
                    let y    = cycH - traveled
                    let x    = p.x * size.width
                    let prog = y / cycH
                    let fade = min(prog / 0.08, (1 - prog) / 0.08, 1.0)

                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - p.size / 2,
                            y: y - p.size / 2,
                            width:  p.size,
                            height: p.size
                        )),
                        with: .color(Color.white.opacity(p.opacity * fade))
                    )
                }
            }
        }
    }
}

#if os(iOS)
private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
#endif

#if os(tvOS)
private struct TVMainTabView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeScreen()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                SearchScreen()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(1)

            NavigationStack {
                LibraryScreen()
            }
            .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
            .tag(2)

            NavigationStack {
                SettingsScreen()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(3)
        }
        .task {
            if let profile = profileManager.currentProfile {
                await addonRepo.loadAddons(profileId: profile.id)
            }
        }
        .onChange(of: profileManager.currentProfile) { _, newProfile in
            if let profile = newProfile {
                Task { await addonRepo.loadAddons(profileId: profile.id) }
            }
        }
    }
}
#endif

struct MainTabView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared

    @State private var selectedTab = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        #if os(tvOS)
        TVMainTabView()
            .environmentObject(profileManager)
            .environmentObject(roleManager)
        #else
        if sizeClass == .regular {
            NavigationSplitView {
                List {
                    Button { selectedTab = 0 } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                    Button { selectedTab = 1 } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    Button { selectedTab = 2 } label: {
                        Label("Library", systemImage: "rectangle.stack.fill")
                    }
                    Button { selectedTab = 3 } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
                .listStyle(.sidebar)
            } detail: {
                tabContent
            }
            .tint(.white)
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
            phoneTabView
            .tint(.blue)
            .modifier(TabBarMinimizeModifier())
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
        #endif
    }

    /// iOS 26 gives the search tab a detached, circular presentation to the right
    /// of the tab pill, and presents its content as a sheet over the current tab
    /// with the bar morphing into the search field. It must be declared last.
    /// On iOS 18 no such role exists, so Search stays an ordinary inline tab and
    /// SearchScreen keeps its own field.
    @ViewBuilder
    private var phoneTabView: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: 0) {
                    HomeScreen()
                }
                Tab("Library", systemImage: "rectangle.stack.fill", value: 2) {
                    LibraryScreen()
                }
                Tab("Settings", systemImage: "gearshape.fill", value: 3) {
                    SettingsScreen()
                }
                Tab(value: 1, role: .search) {
                    SearchScreen()
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: 0) {
                    HomeScreen()
                }
                Tab("Search", systemImage: "magnifyingglass", value: 1) {
                    SearchScreen()
                }
                Tab("Library", systemImage: "rectangle.stack.fill", value: 2) {
                    LibraryScreen()
                }
                Tab("Settings", systemImage: "gearshape.fill", value: 3) {
                    SettingsScreen()
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: HomeScreen()
        case 1: SearchScreen()
        case 2: LibraryScreen()
        case 3: SettingsScreen()
        case 4: AdminDashboard()
        default: HomeScreen()
        }
    }
}

private struct RestrictedAccessView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @AppStorage("moonlit.guestMode") private var guestMode = false
    @State private var animateGlow = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#101114"), Color(hex: "#050506")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(hex: "#FF8A35").opacity(0.34),
                    Color(hex: "#FF8A35").opacity(0.12),
                    .clear
                ],
                center: .init(x: 0.5, y: 0.23),
                startRadius: 8,
                endRadius: 190
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color(hex: "#FF8A35").opacity(animateGlow ? 0.28 : 0.14))
                        .frame(width: 120, height: 120)
                        .blur(radius: 32)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateGlow)

                    Image("AppIconPreview")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color(hex: "#FF8A35").opacity(0.24), radius: 20, y: 10)
                        .shadow(color: .black.opacity(0.40), radius: 18, y: 12)
                }

                Text("Access Restricted")
                    .font(.system(size: 26, weight: .semibold, design: .default))
                    .foregroundStyle(.white)

                Text("Your account has been restricted. Access to Moonlit has been limited.")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                Button(action: {
                    guestMode = false
                    Task { await profileManager.signOut() }
                }) {
                    Text("Sign Out")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear { animateGlow = true }
    }
}
