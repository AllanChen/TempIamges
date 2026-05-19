import AppKit
import Foundation

final class AuthManager {
    static let shared = AuthManager()

    private let apiBase = URL(string: "https://api.mcreator.ai")!
    private let nativeCallback = "glance://auth/callback"
    private let sessionKey = "glance.auth.session"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var cachedSession: AuthSession?

    private init() {
        decoder.keyDecodingStrategy = .useDefaultKeys
        encoder.keyEncodingStrategy = .useDefaultKeys
        cachedSession = loadSessionFromStorage()
    }

    var session: AuthSession? {
        if let cachedSession, cachedSession.isExpired {
            signOut()
            return nil
        }
        return cachedSession
    }

    var isSignedIn: Bool {
        session != nil
    }

    func openGoogleSignIn() {
        guard let url = URL(string: "\(apiBase.absoluteString)/auth/google?client=glance") else { return }
        NSWorkspace.shared.open(url)
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

    func signOut() {
        cachedSession = nil
        deleteSessionFromStorage()
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    private func exchangeNativeCode(_ code: String, completion: @escaping (Result<AuthSession, AuthError>) -> Void) {
        post(path: "/auth/native/exchange", body: ["code": code]) { [weak self] (result: Result<AuthSession, AuthError>) in
            switch result {
            case .success(let session):
                self?.save(session: session)
                completion(.success(session))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func save(session: AuthSession) {
        cachedSession = session
        saveSessionToStorage(session)
        NotificationCenter.default.post(name: .authDidChange, object: nil)
    }

    private func post<Response: Decodable>(
        path: String,
        body: [String: String],
        completion: @escaping (Result<Response, AuthError>) -> Void
    ) {
        let url = apiBase.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                finish(.failure(.message(envelope?.error?.message ?? "Request failed with HTTP \(http.statusCode).")))
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
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    private func loadSessionFromStorage() -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? decoder.decode(AuthSession.self, from: data)
    }

    private func deleteSessionFromStorage() {
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
        guard let date = Self.parseDate(expiresAt) else { return false }
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

struct ApiError: Decodable {
    let code: String?
    let message: String
}

enum AuthError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("AuthManager.authDidChange")
}
