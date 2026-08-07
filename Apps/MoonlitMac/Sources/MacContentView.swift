import SwiftUI
import AppKit
import MoonlitCore

/// Near-black background + warm glow shared by the cold-launch intro and
/// session-restore screens, matching iOS's `SessionRestoreView` splash
/// exactly (same hex values) rather than the app-wide charcoal
/// `MacFusionAmbientBackground` — the splash is meant to read as pure dark
/// with a single warm accent, not the tinted-charcoal look used everywhere
/// else in the app.
enum MacSplashBackground {
    static let gradient = LinearGradient(
        colors: [
            Color(red: 0.063, green: 0.067, blue: 0.078),  // #101114
            Color(red: 0.020, green: 0.020, blue: 0.024),  // #050506
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let glow = Color(red: 1.0, green: 0.541, blue: 0.208)  // #FF8A35
}

struct MacContentView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @AppStorage("moonlit.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("moonlit.guestMode") private var guestMode = false

    /// The launch intro runs once per cold launch. It also covers session
    /// restore, so `SessionRestoreView` is only reached if restore is somehow
    /// still pending after the intro has played out.
    @State private var hasPlayedIntro = false
    /// A cold launch always lands on the profile picker rather than silently
    /// resuming the last profile. Flipped once the user picks, so in-session
    /// switches (PillNavBar / Settings) behave exactly as before.
    @State private var hasChosenProfileThisLaunch = false

    var body: some View {
        Group {
            if !hasPlayedIntro {
                MacLaunchIntroView { hasPlayedIntro = true }
            } else if !profileManager.hasRestoredSession {
                SessionRestoreView()
            } else if !hasSeenOnboarding {
                MacOnboardingView {
                    hasSeenOnboarding = true
                } onSkip: {
                    guestMode = true
                    hasSeenOnboarding = true
                }
            } else if profileManager.isAuthenticated {
                if profileManager.currentProfile != nil && hasChosenProfileThisLaunch {
                    MacMainView()
                } else if !profileManager.profiles.isEmpty {
                    MacProfilePicker { hasChosenProfileThisLaunch = true }
                } else {
                    MacCreateProfile()
                }
            } else {
                MacAuthView()
            }
        }
        .animation(.easeInOut(duration: 0.45), value: hasPlayedIntro)
        .onChange(of: profileManager.currentProfile) { _, newProfile in
            // Selecting a profile — whether from the launch picker or a mid-session
            // switch — is what unlocks the main view.
            if newProfile != nil { hasChosenProfileThisLaunch = true }
        }
        .onChange(of: profileManager.currentProfile) { _, newProfile in
            roleManager.evaluateRole(profile: newProfile)
        }
    }
}

/// Cold-launch intro. Deliberately built on the real Moonlit app icon and
/// wordmark — the same identity as `SessionRestoreView` and the profile picker —
/// rather than an abstract lettering animation, so launch looks like the app.
private struct MacLaunchIntroView: View {
    let onFinished: () -> Void

    @State private var appeared = false
    @State private var settled = false
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            MacSplashBackground.gradient
                .ignoresSafeArea()

            // Soft warm halo behind the mark, breathing up as it settles.
            RadialGradient(
                colors: [
                    MacSplashBackground.glow.opacity(settled ? 0.34 : 0.08),
                    MacSplashBackground.glow.opacity(settled ? 0.12 : 0.03),
                    .clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.1), value: settled)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(MacSplashBackground.glow.opacity(settled ? 0.28 : 0.14))
                        .frame(width: 176, height: 176)
                        .blur(radius: 34)

                    AppIconView()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: MacSplashBackground.glow.opacity(0.34), radius: 34, y: 14)
                        .shadow(color: .black.opacity(0.45), radius: 34, y: 14)
                }
                .scaleEffect(appeared ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)

                Text("Moonlit")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .tracking(1)
                    .padding(.top, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .background(MacIntroKeyCatcher { finish() })
        .onAppear {
            withAnimation(.smooth(duration: 0.7).delay(0.1)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.9).delay(0.5)) { settled = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { finish() }
        }
    }

    /// Idempotent — the timer and the skip gestures race, first one wins.
    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished()
    }
}

/// Makes the intro skippable with the keyboard. SwiftUI has no "any key"
/// handler on macOS, so this drops to an `NSView` that takes first responder
/// and reports the first `keyDown` it sees.
private struct MacIntroKeyCatcher: NSViewRepresentable {
    let onKey: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onKey = onKey
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyView)?.onKey = onKey
    }

    final class KeyView: NSView {
        var onKey: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { onKey?() }
    }
}

private struct SessionRestoreView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            MacSplashBackground.gradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    MacSplashBackground.glow.opacity(0.30),
                    MacSplashBackground.glow.opacity(0.10),
                    .clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(MacSplashBackground.glow.opacity(0.30))
                        .frame(width: 144, height: 144)
                        .blur(radius: 30)

                    AppIconView()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: MacSplashBackground.glow.opacity(0.30), radius: 30, y: 12)
                        .shadow(color: .black.opacity(0.35), radius: 32, y: 12)
                }
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
