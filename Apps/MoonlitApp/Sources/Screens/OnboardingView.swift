import SwiftUI
import MoonlitCore

private struct OnboardingPoster: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let collection: String
    let url: URL
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let scale: CGFloat
}

private let onboardingPosters: [OnboardingPoster] = [
    .init(id: 0, title: "Dune: Part Two", subtitle: "Added to Movie night picks", collection: "Movie night picks", url: URL(string: "https://image.tmdb.org/t/p/w500/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg")!, x: 0.20, y: 0.18, rotation: -8, scale: 0.78),
    .init(id: 1, title: "Severance", subtitle: "Next up in Prestige series", collection: "Prestige series", url: URL(string: "https://image.tmdb.org/t/p/w500/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg")!, x: 0.70, y: 0.16, rotation: 7, scale: 0.84),
    .init(id: 2, title: "Oppenheimer", subtitle: "Added to Awards shelf", collection: "Awards shelf", url: URL(string: "https://image.tmdb.org/t/p/w500/ptpr0kGAckfQkJeJIt8st5dglvd.jpg")!, x: 0.43, y: 0.35, rotation: 2, scale: 1.06),
    .init(id: 3, title: "The Bear", subtitle: "Continue series", collection: "Prestige series", url: URL(string: "https://image.tmdb.org/t/p/w500/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg")!, x: 0.17, y: 0.53, rotation: 5, scale: 0.72),
    .init(id: 4, title: "Past Lives", subtitle: "Added to Quiet dramas", collection: "Quiet dramas", url: URL(string: "https://image.tmdb.org/t/p/w500/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg")!, x: 0.78, y: 0.48, rotation: -6, scale: 0.86),
    .init(id: 5, title: "Arrival", subtitle: "Added to Mind-bending movies", collection: "Mind-bending movies", url: URL(string: "https://image.tmdb.org/t/p/w500/x2FJsf1ElAgr63Y3PNPtJrcmpoe.jpg")!, x: 0.52, y: 0.70, rotation: 8, scale: 0.76),
]

private let moonlitOrange = Color(hex: "#FF8A35")
private let moonlitInk = Color(hex: "#050506")

struct OnboardingView: View {
    @AppStorage("moonlit.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("moonlit.guestMode") private var guestMode = false

    @State private var page = 0
    @State private var selectedPoster = 2

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                OnboardingWelcomePage(onContinue: advance)
                    .tag(0)
                OnboardingPosterPage(selectedPoster: $selectedPoster, onContinue: advance)
                    .tag(1)
                OnboardingCollectionsPage(onContinue: advance)
                    .tag(2)
                OnboardingLoginPage(
                    onSignIn: { hasSeenOnboarding = true },
                    onSkip: { guestMode = true; hasSeenOnboarding = true },
                    onContinue: advance
                )
                .tag(3)
                OnboardingProfilePage(
                    onFinish: { hasSeenOnboarding = true },
                    onSkip: { guestMode = true; hasSeenOnboarding = true }
                )
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                if page < 3 {
                    Button("Skip") {
                        guestMode = true
                        hasSeenOnboarding = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.leading, 24)
                } else {
                    Color.clear.frame(width: 72, height: 1)
                }

                Spacer()

                HStack(spacing: 7) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.white : Color.white.opacity(0.24))
                            .frame(width: index == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.smooth(duration: 0.26), value: page)

                Spacer()
                Color.clear.frame(width: 72, height: 1)
            }
            .padding(.top, 58)
        }
        .background(moonlitInk)
    }

    private func advance() {
        withAnimation(.smooth(duration: 0.36)) {
            page = min(page + 1, 4)
        }
    }
}

private struct OnboardingWelcomePage: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        OnboardingDarkBackground {
            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(moonlitOrange.opacity(0.42))
                        .frame(width: 210, height: 210)
                        .blur(radius: 42)
                    Image("AppIconPreview")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: moonlitOrange.opacity(0.36), radius: 36, y: 16)
                }
                .padding(.bottom, 28)

                Text("Moonlit")
                    .font(.system(size: 42, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)

                Text("A quieter place for the films and shows you care about.")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 42)

                Spacer()

                OnboardingPrimaryButton(title: "Continue", action: onContinue)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 52)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear {
                withAnimation(.smooth(duration: 0.55).delay(0.08)) {
                    appeared = true
                }
            }
        }
    }
}

private struct OnboardingPosterPage: View {
    @Binding var selectedPoster: Int
    let onContinue: () -> Void
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        OnboardingDarkBackground {
            GeometryReader { geo in
                ZStack {
                    ForEach(onboardingPosters) { poster in
                        FloatingPosterCard(
                            poster: poster,
                            isSelected: poster.id == selectedPoster
                        )
                        .position(x: geo.size.width * poster.x, y: geo.size.height * poster.y)
                    }

                    if let selected = onboardingPosters.first(where: { $0.id == selectedPoster }) {
                        LikePill(title: selected.subtitle)
                            .position(
                                x: min(max(geo.size.width * selected.x, 116), geo.size.width - 116),
                                y: max(geo.size.height * selected.y - 128, 118)
                            )
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                            .id(selected.id)
                    }

                    OnboardingBottomCopy(
                        title: "Build your taste",
                        message: "Moonlit keeps your picks organized without turning onboarding into setup work.",
                        buttonTitle: "Continue",
                        action: onContinue
                    )
                }
            }
        }
        .onAppear { startAutoSelection() }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    private func startAutoSelection() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.25))
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.62)) {
                        let currentIndex = onboardingPosters.firstIndex { $0.id == selectedPoster } ?? 0
                        selectedPoster = onboardingPosters[(currentIndex + 1) % onboardingPosters.count].id
                    }
                }
            }
        }
    }
}

private struct OnboardingCollectionsPage: View {
    let onContinue: () -> Void

    private let rows: [(String, [OnboardingPoster])] = [
        ("Mind-bending movies", [onboardingPosters[5], onboardingPosters[0], onboardingPosters[2], onboardingPosters[4]]),
        ("Prestige series", [onboardingPosters[1], onboardingPosters[3], onboardingPosters[4], onboardingPosters[0]]),
        ("Movie night picks", [onboardingPosters[0], onboardingPosters[2], onboardingPosters[5], onboardingPosters[3]])
    ]

    var body: some View {
        OnboardingDarkBackground {
            VStack(spacing: 0) {
                Spacer().frame(height: 106)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(rows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(row.0)
                                .font(.system(size: 15, weight: .medium, design: .default))
                                .foregroundStyle(.white.opacity(0.86))
                                .padding(.horizontal, 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(row.1) { poster in
                                        PosterImage(url: poster.url)
                                            .frame(width: 82, height: 123)
                                            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                }

                Spacer()

                OnboardingBottomCopy(
                    title: "Collections, not chores",
                    message: "Name shelves around how you actually watch: movie nights, comfort rewatches, prestige series.",
                    buttonTitle: "Continue",
                    action: onContinue
                )
            }
        }
    }
}

private struct OnboardingLoginPage: View {
    let onSignIn: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingDarkBackground {
            VStack(spacing: 0) {
                Spacer()

                Image("AppIconPreview")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: moonlitOrange.opacity(0.30), radius: 28, y: 12)
                    .padding(.bottom, 26)

                Text("Sign in when you’re ready")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)

                Text("Use your Moonlit account to sync profiles and collections. You can skip this on first launch.")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 34)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {}) {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                            Text("Sign in with Apple")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                    .opacity(0.42)
                    .disabled(true)

                    OnboardingPrimaryButton(title: "Sign in with email", action: onSignIn)

                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )

                    Button("How profiles work", action: onContinue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
    }
}

private struct OnboardingProfilePage: View {
    let onFinish: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingDarkBackground {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    ProfileBubble(name: "Zain", color: moonlitOrange, size: 82)
                    HStack(spacing: 12) {
                        ProfileBubble(name: "A", color: Color(hex: "#7C88FF"), size: 58)
                        ProfileBubble(name: "+", color: .white.opacity(0.14), size: 58)
                    }
                }
                .padding(.bottom, 34)

                Text("Profiles come after login")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("If your account has profiles, Moonlit opens the chooser. If not, you’ll create your first profile.")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 34)

                Spacer()

                VStack(spacing: 12) {
                    OnboardingPrimaryButton(title: "Finish", action: onFinish)
                    Button(action: onSkip) {
                        Text("Continue without account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
    }
}

private struct FloatingPosterCard: View {
    let poster: OnboardingPoster
    let isSelected: Bool
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        PosterImage(url: poster.url)
            .frame(width: 96, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                    .stroke(.white.opacity(isSelected ? 0.28 : 0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.62 : 0.38), radius: isSelected ? 22 : 12, y: isSelected ? 14 : 8)
            .rotationEffect(.degrees(poster.rotation))
            .scaleEffect(poster.scale * (isSelected ? 1.08 : 0.94))
            .opacity(isSelected ? 1 : 0.34)
            .saturation(isSelected ? 1 : 0.62)
            .offset(y: floatOffset)
            .animation(.smooth(duration: 0.62), value: isSelected)
            .onAppear {
                withAnimation(.easeInOut(duration: Double.random(in: 5.6...7.4)).repeatForever(autoreverses: true)) {
                    floatOffset = CGFloat.random(in: -7 ... -4)
                }
            }
    }
}

private struct LikePill: View {
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "#FF4B68"))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#FF4B68").opacity(0.15), in: Circle())
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.50), radius: 18, y: 8)
    }
}

private struct OnboardingBottomCopy: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 27, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.54))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
            }
            .padding(.bottom, 24)

            OnboardingPrimaryButton(title: buttonTitle, action: action)
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
        }
        .background(
            LinearGradient(
                colors: [.clear, moonlitInk.opacity(0.88), moonlitInk],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 310),
            alignment: .bottom
        )
    }
}

private struct PosterImage: View {
    let url: URL

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.24)))
            case .empty:
                LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.035)], startPoint: .top, endPoint: .bottom)
            @unknown default:
                Color.white.opacity(0.06)
            }
        }
    }
}

private struct ProfileBubble: View {
    let name: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(name)
            .font(.system(size: size > 70 ? 24 : 18, weight: .semibold, design: .default))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.34), radius: 26, y: 12)
            )
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
        .shadow(color: .white.opacity(0.08), radius: 18, y: 8)
    }
}

private struct OnboardingDarkBackground<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            moonlitInk.ignoresSafeArea()
            RadialGradient(
                colors: [moonlitOrange.opacity(0.14), .clear],
                center: .init(x: 0.50, y: 0.27),
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()
            content
        }
    }
}
