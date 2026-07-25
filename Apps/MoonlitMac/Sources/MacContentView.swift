import SwiftUI
import MoonlitCore

struct MacContentView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @AppStorage("moonlit.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("moonlit.guestMode") private var guestMode = false

    var body: some View {
        Group {
            if !profileManager.hasRestoredSession {
                SessionRestoreView()
            } else if !hasSeenOnboarding {
                MacOnboardingView {
                    hasSeenOnboarding = true
                } onSkip: {
                    guestMode = true
                    hasSeenOnboarding = true
                }
            } else if profileManager.isAuthenticated {
                if profileManager.currentProfile != nil {
                    MacMainView()
                } else if !profileManager.profiles.isEmpty {
                    MacProfilePicker()
                } else {
                    MacCreateProfile()
                }
            } else {
                MacAuthView()
            }
        }
        .overlay(alignment: .topTrailing) {
            // `.hiddenTitleBar` still reserves a top safe area for the native
            // traffic-light hit region even though we draw our own controls —
            // without ignoring it here, this padding stacks on top of that
            // invisible inset and the controls sit far lower than intended.
            MacWindowControls()
                .padding(.trailing, 16)
                .padding(.top, 8)
                .ignoresSafeArea(.container, edges: .top)
        }
        .onChange(of: profileManager.currentProfile) { _, newProfile in
            roleManager.evaluateRole(profile: newProfile)
        }
    }
}

private struct SessionRestoreView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            MoonlitTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [MoonlitTheme.accent.opacity(0.18), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AppIconView()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 32, y: 12)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)

                Text("Moonlit")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 60, height: 4)
                    .padding(.top, 24)
                    .opacity(appeared ? 0 : 1)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.55).delay(0.08)) {
                appeared = true
            }
        }
    }
}

// MARK: - Onboarding

private struct MacOnboardingView: View {
    let onFinish: () -> Void
    let onSkip: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack(alignment: .top) {
            MoonlitTheme.background.ignoresSafeArea()

            VStack {
                Spacer()
                Group {
                    if page == 0 { welcomePage }
                    else if page == 1 { collectionsPage }
                    else { signInPage }
                }
                Spacer()
            }

            HStack {
                if page < 2 {
                    Button("Skip") { onSkip() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .padding(.leading, 28)
                } else {
                    Color.clear.frame(width: 72, height: 1)
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.white : Color.white.opacity(0.24))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.smooth(duration: 0.26), value: page)
                Spacer()
                Color.clear.frame(width: 72, height: 1)
            }
            .padding(.top, 42)
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            AppIconView()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 32, y: 12)
            Text("Moonlit")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 20)
            Text("A quieter place for the films and shows you care about.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.top, 8)
            Spacer()
            Button { withAnimation(.smooth(duration: 0.36)) { page = 1 } } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }

    private var collectionsPage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(MoonlitTheme.accent)
                Text("Collections, not chores")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Name shelves around how you actually watch: movie nights, comfort rewatches, prestige series.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 52)
            }
            Spacer()
            Button { withAnimation(.smooth(duration: 0.36)) { page = 2 } } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }

    private var signInPage: some View {
        VStack(spacing: 0) {
            Spacer()
            AppIconView()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            Text("Sign in when you're ready")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
            Text("Use your Moonlit account to sync profiles and collections. You can skip this on first launch.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 52)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 12) {
                Button(action: onFinish) {
                    Text("Sign in with email")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: 320)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }
}
