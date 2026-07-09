import AuthenticationServices
import CryptoKit
import AppKit
import MoonlitCore

/// macOS adaptation of the iOS `AppleSignInCoordinator`. Identical nonce +
/// Supabase id-token flow — only the presentation anchor differs (an `NSWindow`
/// instead of the UIKit key window). Feed the resulting `(idToken, nonce)` into
/// `ProfileManager.signInWithApple(idToken:nonce:)`.
final class MacAppleSignInCoordinator: NSObject, ObservableObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var rawNonce: String?
    var onResult: ((Result<(idToken: String, nonce: String), Error>) -> Void)?

    func performRequest() {
        let nonce = randomNonce()
        rawNonce = nonce
        let hashed = SHA256.hash(data: Data(nonce.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashed

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let nonce = rawNonce else {
            onResult?(.failure(SupabaseError.authFailed("Failed to extract Apple identity token")))
            return
        }
        onResult?(.success((idToken: token, nonce: nonce)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { return }
        onResult?(.failure(error))
    }

    private func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
