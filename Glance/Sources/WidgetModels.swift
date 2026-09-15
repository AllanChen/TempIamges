import AppKit
import CryptoKit
import Foundation

struct WidgetCommand: Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let inputTypes: [String]
    let inputMimeTypes: [String]
    let outputs: [String]
    let taskType: String
    let requiresUpload: Bool
    let parameterSchema: [String: JSONValue]
}

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .string(let v): try container.encode(v); case .number(let v): try container.encode(v); case .bool(let v): try container.encode(v); case .object(let v): try container.encode(v); case .array(let v): try container.encode(v); case .null: try container.encodeNil() }
    }
}

struct WidgetManifest: Codable, Hashable {
    let schemaVersion: Int
    let id: String
    let version: String
    let name: String
    let summary: String
    let author: String
    let iconURL: URL
    let official: Bool
    let execution: WidgetExecution
    let commands: [WidgetCommand]
    let privacy: WidgetPrivacy
    let minimumGlanceVersion: String
    let updatedAt: String
    let signature: WidgetSignature

    func isCompatible(with inputType: String) -> Bool {
        commands.contains { $0.inputTypes.contains(inputType) }
    }

    /// Synchronous client-side checks run before a manifest is submitted to
    /// the review queue. The backend repeats these checks and performs the
    /// authoritative signature/security validation.
    func submissionValidationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion < 1 { issues.append("schemaVersion must be at least 1") }
        if id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$", options: .regularExpression) == nil {
            issues.append("id must be 3–128 characters using letters, numbers, '.', '_' or '-'")
        }
        if version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("version is required") }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("name is required") }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("summary is required") }
        if author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("author is required") }
        if execution.mode.lowercased() != "cloud" { issues.append("execution.mode must be cloud") }
        if commands.isEmpty { issues.append("at least one command is required") }
        var commandIDs = Set<String>()
        for command in commands {
            if command.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("command id is required") }
            if !commandIDs.insert(command.id).inserted { issues.append("duplicate command id: \(command.id)") }
            if command.inputTypes.isEmpty { issues.append("command \(command.id) must declare an input type") }
            if command.outputs.isEmpty { issues.append("command \(command.id) must declare an output type") }
            if command.taskType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("command \(command.id) must declare taskType") }
        }
        if privacy.notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("privacy notice is required") }
        if signature.algorithm != "Ed25519" || signature.value.isEmpty || signature.keyID.isEmpty {
            issues.append("an Ed25519 signature is required")
        }
        return issues
    }

    func unsignedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WidgetError.invalidManifest }
        object.removeValue(forKey: "signature")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

struct WidgetExecution: Codable, Hashable { let mode: String }
struct WidgetPrivacy: Codable, Hashable { let uploadsMedia: Bool; let notice: String }
struct WidgetSignature: Codable, Hashable { let algorithm: String; let keyID: String; let value: String }

enum WidgetError: LocalizedError {
    case invalidManifest, invalidSignature, unavailable
    var errorDescription: String? {
        switch self { case .invalidManifest: return "The Widget manifest is invalid."; case .invalidSignature: return "The Widget signature could not be verified."; case .unavailable: return "The Widget Market is unavailable." }
    }
}

final class WidgetRegistry {
    static let shared = WidgetRegistry()
    static let didChange = Notification.Name("GlanceWidgetRegistryDidChange")
    private let storageKey = "glance.widgets.installed.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var installed: [WidgetManifest]

    private init() { installed = (try? decoder.decode([WidgetManifest].self, from: UserDefaults.standard.data(forKey: storageKey) ?? Data())) ?? [] }

    func install(_ manifest: WidgetManifest) {
        installed.removeAll { $0.id == manifest.id }
        installed.append(manifest)
        if let data = try? encoder.encode(installed) { UserDefaults.standard.set(data, forKey: storageKey) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func uninstall(id: String) {
        installed.removeAll { $0.id == id }
        if let data = try? encoder.encode(installed) { UserDefaults.standard.set(data, forKey: storageKey) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func compatible(with inputType: String) -> [WidgetManifest] { installed.filter { $0.isCompatible(with: inputType) } }
}

final class WidgetCatalogClient {
    static let shared = WidgetCatalogClient()
    private let baseURL = URL(string: "https://glance-service.allanchanni.workers.dev/api/v2/widgets")!
    private let publicKeyData = Data(base64Encoded: "Wqnr5777Qn4T3aN0/3khkXsFbdcf/5l85GrlnccK8/w=")!

    func fetch(widgetID: String, completion: @escaping (Result<WidgetManifest, Error>) -> Void) {
        let url = baseURL.appendingPathComponent(widgetID)
        URLSession.shared.dataTask(with: URLRequest(url: url)) { [weak self] data, response, error in
            guard let self else { return }
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { DispatchQueue.main.async { completion(.failure(WidgetError.unavailable)) }; return }
            do {
                let envelope = try JSONDecoder().decode(WidgetEnvelope.self, from: data)
                guard envelope.success else { throw WidgetError.unavailable }
                guard let manifest = envelope.result else { throw WidgetError.invalidManifest }
                let key = try Curve25519.Signing.PublicKey(rawRepresentation: self.publicKeyData)
                guard manifest.signature.algorithm == "Ed25519",
                      let signature = Data(base64URLEncoded: manifest.signature.value),
                      try key.isValidSignature(signature, for: manifest.unsignedJSON()) else { throw WidgetError.invalidSignature }
                DispatchQueue.main.async { completion(.success(manifest)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }.resume()
    }
    private struct WidgetEnvelope: Codable { let success: Bool; let result: WidgetManifest? }
}

// MARK: - Submission and release workflow

enum WidgetSubmissionStatus: String, Codable {
    case draft, submitted, automatedChecking = "automated_checking", manualReview = "manual_review"
    case testing, grayRelease = "gray_release", published, rejected, suspended, deprecated
}

struct WidgetSubmission: Codable, Hashable, Identifiable {
    let id: String
    let widgetID: String
    let widgetVersion: String
    let authorID: String
    let status: WidgetSubmissionStatus
    let manifest: WidgetManifest
    let testAssetIDs: [String]
    let automatedIssues: [String]
    let reviewNote: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, widgetID = "widget_id", widgetVersion = "widget_version", authorID = "author_id"
        case status, manifest, testAssetIDs = "test_asset_ids", automatedIssues = "automated_issues"
        case reviewNote = "review_note", createdAt = "created_at", updatedAt = "updated_at"
    }
}

struct WidgetReviewDecision: Codable, Hashable {
    let decision: String
    let note: String
    let testPassed: Bool

    enum CodingKeys: String, CodingKey {
        case decision, note, testPassed = "test_passed"
    }
}

struct WidgetRelease: Codable, Hashable, Identifiable {
    let id: String
    let widgetID: String
    let version: String
    let channel: String
    let rolloutPercent: Int
    let status: WidgetSubmissionStatus

    enum CodingKeys: String, CodingKey {
        case id, widgetID = "widget_id", version, channel
        case rolloutPercent = "rollout_percent", status
    }
}

/// Authenticated API surface for the developer and reviewer portals. The
/// server remains authoritative: this client only submits declarations and
/// displays workflow state; it never executes third-party code locally.
final class WidgetPlatformClient {
    static let shared = WidgetPlatformClient()
    private let baseURL = URL(string: "https://glance-service.allanchanni.workers.dev/api/v2")!
    private let session = URLSession(configuration: .ephemeral)
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func submit(manifest: WidgetManifest, testAssetIDs: [String] = [],
                completion: @escaping (Result<WidgetSubmission, Error>) -> Void) {
        let issues = manifest.submissionValidationIssues()
        guard issues.isEmpty else {
            completion(.failure(WidgetPlatformError.validation(issues)))
            return
        }
        request(path: "widget-submissions", method: "POST",
                body: SubmissionRequest(manifest: manifest, testAssetIDs: testAssetIDs),
                completion: completion)
    }

    func fetchSubmission(id: String, completion: @escaping (Result<WidgetSubmission, Error>) -> Void) {
        request(path: "widget-submissions/\(id.pathComponentEscaped)", method: "GET", completion: completion)
    }

    func review(submissionID: String, decision: WidgetReviewDecision,
                completion: @escaping (Result<WidgetSubmission, Error>) -> Void) {
        request(path: "widget-submissions/\(submissionID.pathComponentEscaped)/review", method: "POST", body: decision, completion: completion)
    }

    func promote(releaseID: String, rolloutPercent: Int,
                 completion: @escaping (Result<WidgetRelease, Error>) -> Void) {
        request(path: "widget-releases/\(releaseID.pathComponentEscaped)/promote", method: "POST",
                body: RolloutRequest(rolloutPercent: max(0, min(100, rolloutPercent))), completion: completion)
    }

    func suspend(releaseID: String, reason: String,
                 completion: @escaping (Result<WidgetRelease, Error>) -> Void) {
        request(path: "widget-releases/\(releaseID.pathComponentEscaped)/suspend", method: "POST",
                body: SuspendRequest(reason: reason), completion: completion)
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String,
                                                                body: Body? = nil,
                                                                completion: @escaping (Result<Response, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.session?.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try? encoder.encode(body) }
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            do {
                if let error { throw error }
                guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WidgetPlatformError.unavailable }
                let envelope = try self.decoder.decode(PlatformEnvelope<Response>.self, from: data)
                guard envelope.success, let result = envelope.result else { throw WidgetPlatformError.server(envelope.error?.message ?? "Request failed") }
                DispatchQueue.main.async { completion(.success(result)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }.resume()
    }

    private func request<Response: Decodable>(path: String, method: String,
                                              completion: @escaping (Result<Response, Error>) -> Void) {
        request(path: path, method: method, body: Optional<EmptyBody>.none, completion: completion)
    }

    private struct SubmissionRequest: Codable { let manifest: WidgetManifest; let testAssetIDs: [String]; enum CodingKeys: String, CodingKey { case manifest; case testAssetIDs = "test_asset_ids" } }
    private struct RolloutRequest: Codable { let rolloutPercent: Int; enum CodingKeys: String, CodingKey { case rolloutPercent = "rollout_percent" } }
    private struct SuspendRequest: Codable { let reason: String }
    private struct EmptyBody: Codable {}
    private struct PlatformEnvelope<Result: Decodable>: Decodable { let success: Bool; let result: Result?; let error: PlatformError? }
    private struct PlatformError: Decodable { let message: String? }
}

enum WidgetPlatformError: LocalizedError {
    case validation([String]), server(String), unavailable
    var errorDescription: String? {
        switch self {
        case .validation(let issues): return issues.joined(separator: "; ")
        case .server(let message): return message
        case .unavailable: return WidgetError.unavailable.localizedDescription
        }
    }
}

private extension String {
    var pathComponentEscaped: String { addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var string = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        string += String(repeating: "=", count: (4 - string.count % 4) % 4)
        self.init(base64Encoded: string)
    }
}
