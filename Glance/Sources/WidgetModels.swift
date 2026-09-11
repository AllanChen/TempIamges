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

    func compatible(with inputType: String) -> [WidgetManifest] { installed.filter { $0.isCompatible(with: inputType) } }
}

final class WidgetCatalogClient {
    static let shared = WidgetCatalogClient()
    private let baseURL = URL(string: "https://api.mcreator.ai/api/glance/v2/widgets")!
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

private extension Data {
    init?(base64URLEncoded value: String) {
        var string = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        string += String(repeating: "=", count: (4 - string.count % 4) % 4)
        self.init(base64Encoded: string)
    }
}
