import AppKit
import Foundation
import CryptoKit
import Security

final class AuthManager {
    static let shared = AuthManager()

    private let apiBase = URL(string: "https://api.glance.mcreator.ai")!
    private let nativeCallback = "glance://auth/callback"
    private let sessionKey = "glance.auth.session"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let sessionLock = NSLock()
    private var cachedSession: AuthSession?
    private var pendingOAuth: (state: String, verifier: String)?

    private init() {
        decoder.keyDecodingStrategy = .useDefaultKeys
        encoder.keyEncodingStrategy = .useDefaultKeys
        cachedSession = loadSessionFromStorage()
    }

    var session: AuthSession? {
        sessionLock.lock()
        let value = cachedSession
        sessionLock.unlock()
        if let value, value.isExpired {
            return nil
        }
        return value
    }

    var storedUserID: Int? { sessionLock.lock(); defer { sessionLock.unlock() }; return cachedSession?.user.id }

    var isSignedIn: Bool {
        session != nil
    }

    func openGoogleSignIn() {
        let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        pendingOAuth = (state, verifier)
        var components = URLComponents(url: apiBase.appendingPathComponent("auth/google"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "client", value: "glance"),
                                URLQueryItem(name: "state", value: state), URLQueryItem(name: "code_challenge", value: challenge),
                                URLQueryItem(name: "device_id", value: BillingIdentity.deviceID)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    func sendEmailCode(email: String, completion: @escaping (Result<EmailCodeResponse, AuthError>) -> Void) {
        post(path: "/auth/email/send-code", body: ["email": email], completion: completion)
    }

    func verifyEmailCode(email: String, code: String, completion: @escaping (Result<AuthSession, AuthError>) -> Void) {
        let body = [
            "email": email,
            "code": code,
            "redirect_uri": nativeCallback,
        ]
        post(path: "/auth/email/verify-code", body: body) { [weak self] (result: Result<EmailVerifyResponse, AuthError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let session = response.session {
                    self.pendingOAuth = nil
                    self.save(session: session)
                    completion(.success(session))
                } else if let code = response.code {
                    self.exchangeNativeCode(code, completion: completion)
                } else {
                    completion(.failure(.message("Sign-in response did not include a session code.")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func handleCallbackURL(_ url: URL, completion: @escaping (Result<AuthSession, AuthError>) -> Void) {
        guard url.scheme == "glance", url.host == "auth", url.path == "/callback" else {
            completion(.failure(.message("Unsupported callback URL.")))
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let pendingOAuth,
              components?.queryItems?.first(where: { $0.name == "state" })?.value == pendingOAuth.state else {
            completion(.failure(.message("This sign-in request expired. Please sign in again.".localized)))
            return
        }
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            completion(.failure(.message(error)))
            return
        }
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            completion(.failure(.message("Callback URL did not include a code.")))
            return
        }
        exchangeNativeCode(code, completion: completion)
    }

    func invalidateOnlineSession() {
        sessionLock.lock()
        let expired = cachedSession.map { AuthSession(user: $0.user, token: $0.token, expiresAt: "2000-01-01T00:00:00Z") }
        cachedSession = expired; sessionLock.unlock()
        if let expired { saveSessionToStorage(expired) }; notifyChange()
    }

    func signOut() {
        sessionLock.lock()
        let token = cachedSession?.token
        cachedSession = nil
        sessionLock.unlock()
        pendingOAuth = nil
        deleteSessionFromStorage()
        notifyChange()
        if let token {
            var request = URLRequest(url: apiBase.appendingPathComponent("auth/logout"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request).resume()
        }
    }

    private func exchangeNativeCode(_ code: String, completion: @escaping (Result<AuthSession, AuthError>) -> Void) {
        guard let pending = pendingOAuth else {
            completion(.failure(.message("Please start sign-in again.".localized)))
            return
        }
        post(path: "/auth/native/exchange", body: ["code": code, "code_verifier": pending.verifier]) { [weak self] (result: Result<AuthSession, AuthError>) in
            switch result {
            case .success(let session):
                self?.pendingOAuth = nil
                self?.save(session: session)
                completion(.success(session))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func save(session: AuthSession) {
        sessionLock.lock()
        cachedSession = session
        sessionLock.unlock()
        saveSessionToStorage(session)
        notifyChange()
    }

    private func notifyChange() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .authDidChange, object: nil) }
    }

    func updateCredits(_ credits: Int, forToken expectedToken: String? = nil) {
        sessionLock.lock()
        guard let current = cachedSession, expectedToken == nil || current.token == expectedToken,
              let data = try? encoder.encode(current.user),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { sessionLock.unlock(); return }
        object["credits"] = credits
        guard let updated = try? JSONSerialization.data(withJSONObject: object),
              let user = try? decoder.decode(AuthUser.self, from: updated) else { sessionLock.unlock(); return }
        let value = AuthSession(user: user, token: current.token, expiresAt: current.expiresAt)
        cachedSession = value; sessionLock.unlock()
        saveSessionToStorage(value); notifyChange()
    }

    func refreshAccount(completion: ((Result<AuthUser, AuthError>) -> Void)? = nil) {
        guard let current = session else {
            completion?(.failure(.message("Please sign in to use Widgets.".localized)))
            return
        }
        var request = URLRequest(url: apiBase.appendingPathComponent("auth/me"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(current.token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.session?.token == current.token else {
                    completion?(.failure(.message("Please sign in to use Widgets.".localized)))
                    return
                }
                if (response as? HTTPURLResponse)?.statusCode == 401 {
                    self.invalidateOnlineSession()
                    completion?(.failure(.message("Please sign in to use Widgets.".localized)))
                } else if error == nil, let data,
                          let envelope = try? JSONDecoder().decode(ApiEnvelope<AccountResponse>.self, from: data),
                          envelope.success, let result = envelope.result {
                    self.save(session: AuthSession(user: result.user, token: current.token, expiresAt: current.expiresAt))
                    completion?(.success(result.user))
                } else {
                    completion?(.failure(.message(error?.localizedDescription ?? "Could not refresh your account.".localized)))
                }
            }
        }.resume()
    }

    private struct AccountResponse: Decodable { let user: AuthUser }

    private func post<Response: Decodable>(
        path: String,
        body: [String: String],
        completion: @escaping (Result<Response, AuthError>) -> Void
    ) {
        let url = apiBase.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BillingIdentity.deviceID, forHTTPHeaderField: "X-Glance-Device")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let finish: (Result<Response, AuthError>) -> Void = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            if let error {
                finish(.failure(.message(error.localizedDescription)))
                return
            }
            guard let data else {
                finish(.failure(.message("Empty server response.")))
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
                let envelope = try? self?.decoder.decode(ApiEnvelope<Response>.self, from: data)
                if let issue=envelope?.error {finish(.failure(.server(code:issue.code ?? "request_failed",message:issue.message,attemptsRemaining:issue.details?.attemptsRemaining)))}
                else {finish(.failure(.message("Request failed with HTTP \(http.statusCode).")))}
                return
            }

            do {
                let envelope = try self?.decoder.decode(ApiEnvelope<Response>.self, from: data)
                if let result = envelope?.result, envelope?.success == true {
                    finish(.success(result))
                } else {
                    finish(.failure(.message(envelope?.error?.message ?? "Request failed.")))
                }
            } catch {
                finish(.failure(.message("Could not read server response.")))
            }
        }.resume()
    }

    private func saveSessionToStorage(_ session: AuthSession) {
        guard let data = try? encoder.encode(session) else { return }
        UserDefaults.standard.set(true, forKey: sessionKey + ".keychainRollbackComplete")
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    private func loadSessionFromStorage() -> AuthSession? {
        let marker = sessionKey + ".keychainRollbackComplete"
        if let data = UserDefaults.standard.data(forKey: sessionKey) {
            UserDefaults.standard.set(true, forKey: marker)
            return try? decoder.decode(AuthSession.self, from: data)
        }
        guard !UserDefaults.standard.bool(forKey: marker) else { return nil }
        UserDefaults.standard.set(true, forKey: marker)
        // One-time, noninteractive recovery of sessions written by the reverted
        // Keychain storage. A denied read never opens a password dialog.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.mcreator.glance.auth",
            kSecAttrAccount as String: sessionKey,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let session = try? decoder.decode(AuthSession.self, from: data) else { return nil }
        UserDefaults.standard.set(data, forKey: sessionKey)
        return session
    }

    private func deleteSessionFromStorage() {
        UserDefaults.standard.set(true, forKey: sessionKey + ".keychainRollbackComplete")
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

}

struct AuthSession: Codable {
    let user: AuthUser
    let token: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case user
        case token
        case expiresAt = "expires_at"
    }

    var isExpired: Bool {
        guard let date = Self.parseDate(expiresAt) else { return true }
        return date <= Date()
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

struct AuthUser: Codable {
    let id: Int
    let credits: Int?
    let email: String
    let googleId: String?
    let name: String?
    let avatarUrl: String?
    let role: String
    let authProvider: String
    let emailVerified: Bool
    let status: String
    let createdAt: String
    let updatedAt: String
    let lastLoginAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case credits
        case email
        case googleId = "google_id"
        case name
        case avatarUrl = "avatar_url"
        case role
        case authProvider = "auth_provider"
        case emailVerified = "email_verified"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastLoginAt = "last_login_at"
    }
}

struct EmailCodeResponse: Codable {
    let email: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case email
        case expiresAt = "expires_at"
    }
}

struct EmailVerifyResponse: Codable {
    let user: AuthUser?
    let token: String?
    let expiresAt: String?
    let code: String?
    let redirectUrl: String?

    enum CodingKeys: String, CodingKey {
        case user
        case token
        case expiresAt = "expires_at"
        case code
        case redirectUrl = "redirect_url"
    }

    var session: AuthSession? {
        guard let user, let token, let expiresAt else { return nil }
        return AuthSession(user: user, token: token, expiresAt: expiresAt)
    }
}

struct ApiEnvelope<ResultType: Decodable>: Decodable {
    let success: Bool
    let result: ResultType?
    let error: ApiError?
}

struct AuthErrorDetails: Decodable {let attemptsRemaining:Int?}
struct ApiError: Decodable {
    let details:AuthErrorDetails?
    let code: String?
    let message: String
}

enum AuthError: LocalizedError {
    case message(String)
    case server(code:String,message:String,attemptsRemaining:Int?)

    var errorDescription: String? {
        switch self {
        case .message(let message):return message.localized
        case .server(_,let message,_):return message.localized
        }
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("AuthManager.authDidChange")
}
