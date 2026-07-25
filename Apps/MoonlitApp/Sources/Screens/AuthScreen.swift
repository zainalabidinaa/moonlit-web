import SwiftUI
import MoonlitCore

struct AuthScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @AppStorage("moonlit.guestMode") private var guestMode = false

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resetEmail = ""
    @State private var showReset = false
    @State private var resetLoading = false
    @State private var resetSent = false
    @StateObject private var appleCoordinator = AppleSignInCoordinator()

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

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 92)

                    ZStack {
                        Circle()
                            .fill(Color(hex: "#FF8A35").opacity(0.34))
                            .frame(width: 178, height: 178)
                            .blur(radius: 36)

                        Image("AppIconPreview")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: Color(hex: "#FF8A35").opacity(0.34), radius: 34, y: 14)
                            .shadow(color: .black.opacity(0.50), radius: 28, y: 18)
                    }
                    .padding(.bottom, 24)

                    Text("Moonlit")
                        .font(.system(size: 40, weight: .semibold, design: .default))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)

                    Text("Sign in to sync profiles and collections.")
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 34)

                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            )

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 28)

                    HStack {
                        Spacer()
                        Button(action: { showReset = true }) {
                            Text("Forgot password?")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "#FF8A35").opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 6)

                    if showReset {
                        VStack(spacing: 10) {
                            TextField("Email address", text: $resetEmail)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 15, weight: .regular, design: .default))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                                        .stroke(.white.opacity(0.10), lineWidth: 1)
                                )

                            if resetSent {
                                Text("Check your email for a reset link.")
                                    .font(.system(size: 12, weight: .regular, design: .default))
                                    .foregroundStyle(Color(hex: "#4ADE80"))
                                    .multilineTextAlignment(.center)
                            }

                            HStack(spacing: 10) {
                                Button(action: { showReset = false; resetSent = false }) {
                                    Text("Cancel")
                                        .font(.system(size: 14, weight: .medium, design: .default))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 20)
                                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
                                }

                                Button(action: sendReset) {
                                    HStack(spacing: 6) {
                                        if resetLoading {
                                            LottieLoadingView(size: 14)
                                        }
                                        Text("Send Reset Link")
                                    }
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundStyle(.black)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 20)
                                    .background(Color(hex: "#FF8A35"), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
                                }
                                .disabled(resetEmail.isEmpty || resetLoading)
                                .opacity(resetEmail.isEmpty || resetLoading ? 0.5 : 1)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "#FF6B6B"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 12)
                    }

                    Spacer().frame(height: 24)

                    VStack(spacing: 12) {
                        Button(action: startAppleSignIn) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                Text("Sign in with Apple")
                            }
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                        }
                        .disabled(isLoading)

                        Button(action: performAuth) {
                            HStack(spacing: 10) {
                                if isLoading {
                                    LottieLoadingView(size: 20)
                                }
                                Text("Sign in")
                            }
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(.white, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
                        }
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity(isLoading || email.isEmpty || password.isEmpty ? 0.48 : 1)

                        Button(action: skipLogin) {
                            Text("Skip login")
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

                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 52)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func performAuth() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await profileManager.signIn(email: email, password: password)
                guestMode = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func skipLogin() {
        guestMode = true
    }

    private func startAppleSignIn() {
        isLoading = true
        errorMessage = nil
        appleCoordinator.onResult = { result in
            Task { @MainActor in
                switch result {
                case .success(let creds):
                    do {
                        try await profileManager.signInWithApple(idToken: creds.idToken, nonce: creds.nonce)
                        guestMode = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
        appleCoordinator.performRequest()
    }

    private func sendReset() {
        guard !resetEmail.isEmpty else { return }
        resetLoading = true
        errorMessage = nil
        Task {
            do {
                try await SupabaseAuth.shared.resetPassword(email: resetEmail.trimmingCharacters(in: .whitespaces))
                resetSent = true
            } catch {
                errorMessage = error.localizedDescription
            }
            resetLoading = false
        }
    }
}

#if os(tvOS)
struct TVAuthScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @AppStorage("moonlit.guestMode") private var guestMode = false
    @AppStorage("moonlit.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showDeviceCode = false
    @State private var deviceCode: String = ""
    @State private var verificationURL: String = "moonlit.app/activate"
    @State private var isPolling = false
    @State private var errorMessage: String?

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

            VStack(spacing: 36) {
                Spacer()

                Image("AppIconPreview")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: Color(hex: "#FF8A35").opacity(0.34), radius: 34, y: 14)

                VStack(spacing: 8) {
                    Text("Moonlit")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Sign in to sync your profiles and collections")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if showDeviceCode {
                    VStack(spacing: 20) {
                        Text("Enter this code at")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text(verificationURL)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)

                        Text(deviceCode)
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 24)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))

                        if isPolling {
                            ProgressView()
                                .scaleEffect(1.2)
                        }
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 16) {
                    Button("Sign In") {
                        showDeviceCode = true
                        startDeviceCodeFlow()
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    Button("Continue as Guest") {
                        guestMode = true
                        hasSeenOnboarding = true
                    }
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
                    .frame(height: 60)
            }
            .padding()
        }
    }

    private func startDeviceCodeFlow() {
        isPolling = true
        let code = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            .shuffled()
            .prefix(6)
            .map(String.init)
            .joined()
        deviceCode = code
        errorMessage = "Device-code sign in coming soon. Use Guest mode for now."
        isPolling = false
    }
}
#endif
