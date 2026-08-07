import SwiftUI
import MoonlitCore
import AppKit

struct MacAuthView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground.baseGradient
                .ignoresSafeArea()
            HStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    Spacer()

                    AppIconView()
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.35), radius: 20)

                    Text("Moonlit")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text("Sign in to your media hub")
                        .font(.system(size: 13))
                        .foregroundColor(MoonlitTheme.textTertiary)

                    VStack(spacing: 10) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(MoonlitTheme.surface)
                            .cornerRadius(MoonlitTheme.radiusControl)
                            .overlay(
                                RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .frame(width: 320)
                            .foregroundColor(.white)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(MoonlitTheme.surface)
                            .cornerRadius(MoonlitTheme.radiusControl)
                            .overlay(
                                RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .frame(width: 320)
                            .foregroundColor(.white)

                        if isSignUp {
                            TextField("Invite Code", text: $inviteCode)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(MoonlitTheme.surface)
                                .cornerRadius(MoonlitTheme.radiusControl)
                                .overlay(
                                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                                .frame(width: 320)
                                .foregroundColor(.white)
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .frame(width: 320)
                    }

                    Button(action: performAuth) {
                        HStack(spacing: 8) {
                            if isLoading {
                                MacStrokeSpinner(size: 18, color: .black)
                            }
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(width: 320, height: 42)
                    }
                    .buttonStyle(MoonlitPrimaryButtonStyle(cornerRadius: MoonlitTheme.radiusControl))
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Button(isSignUp ? "Have an account? Sign In" : "New to Moonlit? Create Account") {
                        isSignUp.toggle()
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .font(.system(size: 13))

                    Spacer()
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MoonlitTheme.background)
    }

    private func performAuth() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await profileManager.signUp(
                        email: email, password: password, inviteCode: inviteCode
                    )
                } else {
                    try await profileManager.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = formatError(error)
            }
            isLoading = false
        }
    }

    private func formatError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("data couldn't be read") || msg.contains("missing") {
            return "Connection failed — check your internet and try again"
        }
        if msg.contains("Invalid login") || msg.contains("401") {
            return "Invalid email or password"
        }
        if msg.count > 100 {
            return "Something went wrong — please try again"
        }
        return msg
    }
}

struct AppIconView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSApp.applicationIconImage
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}
