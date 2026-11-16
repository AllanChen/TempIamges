#if MAS
import AppKit
import AuthenticationServices
import CryptoKit

/// Sign in with Apple for the App Store build. The raw nonce goes to the
/// Glance service; Apple signs its SHA-256 into the identity token, so a
/// token taken from another sign-in can't be replayed. On success the session
/// is saved and `.authDidChange` resumes whatever asked for sign-in.
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate,
                         ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignIn()

    private var controller: ASAuthorizationController?
    private var nonce = ""
    private weak var anchor: NSWindow?
    private var completion: ((Result<AuthSession, AuthError>) -> Void)?

    /// The Apple button style that reads on the current panel theme.
    static var buttonStyle: ASAuthorizationAppleIDButton.Style {
        (PanelStyle.windowAppearance ?? NSApp.effectiveAppearance)
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    func start(from window: NSWindow?, completion: @escaping (Result<AuthSession, AuthError>) -> Void) {
        nonce = (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        anchor = window
        self.completion = completion
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            finish(.failure(.message("Apple didn't return a sign-in token. Please try again.")))
            return
        }
        AuthManager.shared.signInWithApple(identityToken: token, nonce: nonce) { [weak self] result in
            self?.finish(result)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            finish(.failure(.message("Sign in with Apple was cancelled.")))
        } else {
            finish(.failure(.message(
                "Sign in with Apple didn't finish. Check that you're signed in to your Apple ID in System Settings, then try again.")))
        }
    }

    private func finish(_ result: Result<AuthSession, AuthError>) {
        let completion = self.completion
        self.completion = nil
        controller = nil
        DispatchQueue.main.async { completion?(result) }
    }
}
#endif
