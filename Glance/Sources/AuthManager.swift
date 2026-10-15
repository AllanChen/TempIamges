import AppKit
import Foundation

final class AuthManager {
    static let shared = AuthManager()

    private let apiBase = URL(string: "https://glance-service.allanchanni.workers.dev")!
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
        if let token = cachedSession?.token {
            var request = URLRequest(url: apiBase.appendingPathComponent("auth/logout"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request).resume()
        }
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
    static let billingDidChange = Notification.Name("BillingClient.billingDidChange")
}

/// Payment operations deliberately use the signed-in user's service token. The
/// hosted checkout URL is short-lived and contains a buyer token, so it is never
/// saved to UserDefaults or logged.
final class BillingClient {
    static let shared = BillingClient()

    private let apiBase = URL(string: "https://glance-service.allanchanni.workers.dev/api/v2/billing")!
    private let decoder = JSONDecoder()

    private init() {}

    func fetchWallet(completion: @escaping (Result<BillingWallet, AuthError>) -> Void) {
        send(path: "wallet", completion: completion)
    }

    func fetchCatalog(completion: @escaping (Result<BillingCatalog, AuthError>) -> Void) {
        send(path: "catalog", completion: completion)
    }

    func startCheckout(sku: String, completion: @escaping (Result<String, AuthError>) -> Void) {
        send(path: "checkout", method: "POST", body: ["sku": sku]) { (result: Result<BillingCheckout, AuthError>) in
            switch result {
            case .success(let checkout):
                guard let url = URL(string: checkout.checkoutUrl), url.scheme == "https" else {
                    completion(.failure(.message("Invalid checkout URL.")))
                    return
                }
                if NSWorkspace.shared.open(url) {
                    completion(.success(checkout.orderId))
                } else {
                    completion(.failure(.message("Could not open checkout in a browser.")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchOrder(id: String, completion: @escaping (Result<BillingOrder, AuthError>) -> Void) {
        send(path: "orders/\(id)", completion: completion)
    }

    func handlePaymentCallback(_ url: URL) {
        guard url.scheme == "glance", url.host == "payment", url.path == "/callback",
              let orderID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "order" })?.value,
              orderID.hasPrefix("order_"), UUID(uuidString: String(orderID.dropFirst(6))) != nil else { return }
        pollOrder(id: orderID, attemptsRemaining: 15)
    }

    private func pollOrder(id: String, attemptsRemaining: Int) {
        fetchOrder(id: id) { [weak self] result in
            switch result {
            case .success(let order):
                if order.status != "pending" {
                    NotificationCenter.default.post(name: .billingDidChange, object: order)
                } else if attemptsRemaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.pollOrder(id: id, attemptsRemaining: attemptsRemaining - 1)
                    }
                }
            case .failure(let error):
                Logger.warning("Payment status check failed: \(error.localizedDescription)")
            }
        }
    }

    private func send<ResultType: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        completion: @escaping (Result<ResultType, AuthError>) -> Void
    ) {
        guard let token = AuthManager.shared.session?.token else {
            DispatchQueue.main.async { completion(.failure(.message("Sign in to continue."))) }
            return
        }
        var request = URLRequest(url: apiBase.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: request) { [decoder = self.decoder] data, response, networkError in
            let result: Result<ResultType, AuthError>
            if let networkError {
                result = .failure(.message(networkError.localizedDescription))
            } else if let data {
                let envelope = try? decoder.decode(ApiEnvelope<ResultType>.self, from: data)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   envelope?.success == true, let value = envelope?.result {
                    result = .success(value)
                } else {
                    result = .failure(.message(envelope?.error?.message ?? "Payment request failed."))
                }
            } else {
                result = .failure(.message("Empty server response."))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

struct BillingWallet: Decodable {
    let balance: Int
    let proLifetime: Bool
    let updatesUntil: String?
    let trialUntil: String
    let trialActive: Bool
}

struct BillingCatalog: Decodable {
    let currency: String
    let products: [BillingProduct]
}

struct BillingProduct: Decodable {
    let sku: String
    let price: String
    let credits: Int
    let label: String
}

struct BillingCheckout: Decodable {
    let orderId: String
    let checkoutUrl: String
    let expiresAt: String
}

struct BillingOrder: Decodable {
    let id: String
    let sku: String
    let currency: String
    let amount: String
    let grantedCredits: Int
    let status: String
    let createdAt: String
    let completedAt: String?
    let refundedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, sku, currency, amount, status
        case grantedCredits = "granted_credits"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case refundedAt = "refunded_at"
    }
}
