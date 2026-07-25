import SwiftUI
import MoonlitCore

struct ConnectAppleIDButton: View {
    @EnvironmentObject private var profileManager: ProfileManager
    @StateObject private var coordinator = AppleSignInCoordinator()
    @State private var appleIdentityId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConnectConfirm = false
    @State private var showDisconnectConfirm = false

    private var isLinked: Bool { appleIdentityId != nil }

    var body: some View {
        // Compact single-line row, sized to sit directly under the profile card in
        // the Settings identity block rather than as a standalone card at the
        // bottom of the screen. Behaviour below is unchanged.
        Button(action: isLinked ? { showDisconnectConfirm = true } : { showConnectConfirm = true }) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                Text("Apple ID")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Circle()
                        .fill(isLinked ? Color.green : Color.white.opacity(0.28))
                        .frame(width: 6, height: 6)
                    Text(isLinked ? "Connected" : "Not connected")
                        .font(.system(size: 12.5))
                        .foregroundColor(isLinked ? .green : MoonlitTheme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
        // ── Connect confirmation ──
        .confirmationDialog("Connect Apple ID", isPresented: $showConnectConfirm, titleVisibility: .visible) {
            Button("Link Apple ID to This Account") { startLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple will show a sign-in prompt. This links your Apple ID to your existing Moonlit account — it won't create a new one.")
        }
        // ── Disconnect confirmation ──
        .confirmationDialog("Disconnect Apple ID", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect Apple ID", role: .destructive) { unlink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer be able to sign in with Apple ID. You can reconnect it at any time.")
        }
        // ── Error alert ──
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await checkLink() }
    }

    private func checkLink() async {
        isLoading = true
        appleIdentityId = try? await profileManager.fetchAppleIdentityId()
        isLoading = false
    }

    private func startLink() {
        coordinator.onResult = { result in
            Task { @MainActor in
                switch result {
                case .success(let creds):
                    isLoading = true
                    do {
                        try await profileManager.linkAppleAccount(idToken: creds.idToken, nonce: creds.nonce)
                        appleIdentityId = try? await profileManager.fetchAppleIdentityId()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
        coordinator.performRequest()
    }

    private func unlink() {
        guard let id = appleIdentityId else { return }
        Task {
            isLoading = true
            do {
                try await profileManager.unlinkAppleAccount(identityId: id)
                appleIdentityId = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
