import Foundation
import UniformTypeIdentifiers

enum WidgetTaskPhase: String, Codable {
    case uploading, submitting, processing, downloading, completed, failed, interrupted
    var isActive: Bool { [.uploading, .submitting, .processing, .downloading].contains(self) }
}

final class WidgetTaskClient {
    static let shared = WidgetTaskClient()
    private let apiBase = URL(string: "https://api.mcreator.ai/api/glance/v2")!
    private let session = URLSession(configuration: .ephemeral)

    func run(widgetID: String, commandID: String, mediaURL: URL,
             progress: @escaping (WidgetTaskPhase, Int) -> Void,
             submitted: @escaping (String) -> Void,
             completion: @escaping (Result<URL, Error>) -> Void) {
        progress(.uploading, 0)
        uploadIfNeeded(mediaURL) { [weak self] upload in
            guard let self else { return }
            switch upload {
            case .failure(let error): completion(.failure(error))
            case .success(let url):
                progress(.submitting, 0)
                self.submit(widgetID: widgetID, commandID: commandID, mediaURL: url) { submission in
                    switch submission {
                    case .failure(let error): completion(.failure(error))
                    case .success(let taskID):
                        submitted(taskID); progress(.processing, 0)
                        self.poll(taskID: taskID, started: Date(), progress: progress, completion: completion)
                    }
                }
            }
        }
    }

    func resume(taskID: String, progress: @escaping (WidgetTaskPhase, Int) -> Void,
                completion: @escaping (Result<URL, Error>) -> Void) {
        progress(.processing, 0)
        poll(taskID: taskID, started: Date(), progress: progress, completion: completion)
    }

    private func uploadIfNeeded(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard url.isFileURL else { completion(.success(url.absoluteString)); return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                var request = URLRequest(url: self.apiBase.appendingPathComponent("uploads")); request.httpMethod = "POST"
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
                body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
                self.session.dataTask(with: request) { data, response, error in
                    do {
                        if let error { throw error }
                        let envelope: UploadEnvelope = try Self.decode(data, response)
                        guard envelope.success, let value = envelope.result?.url else { throw WidgetError.unavailable }
                        completion(.success(value))
                    } catch { completion(.failure(error)) }
                }.resume()
            } catch { completion(.failure(error)) }
        }
    }

    private func submit(widgetID: String, commandID: String, mediaURL: String,
                        completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: apiBase.appendingPathComponent("tasks")); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["widgetID": widgetID, "commandID": commandID, "taskParams": ["url": mediaURL]])
        session.dataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let taskID = envelope.result?.taskID else { throw WidgetError.unavailable }
                completion(.success(taskID))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    private func poll(taskID: String, started: Date,
                      progress: @escaping (WidgetTaskPhase, Int) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void) {
        guard Date().timeIntervalSince(started) <= 1800 else { completion(.failure(WidgetError.unavailable)); return }
        let request = URLRequest(url: apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let result = envelope.result else { throw WidgetError.unavailable }
                if result.status == "completed", let raw = result.resultURL, let url = URL(string: raw) { completion(.success(url)); return }
                if result.status == "failed" { completion(.failure(WidgetError.unavailable)); return }
                progress(.processing, result.processCount ?? 0)
            } catch { /* transient query errors retry until the overall timeout */ }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { self.poll(taskID: taskID, started: started, progress: progress, completion: completion) }
        }.resume()
    }

    private static func decode<T: Decodable>(_ data: Data?, _ response: URLResponse?) throws -> T {
        guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WidgetError.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private struct UploadEnvelope: Codable { let success: Bool; let result: UploadResult? }
    private struct UploadResult: Codable { let url: String }
    private struct TaskEnvelope: Codable { let success: Bool; let result: TaskResult? }
    private struct TaskResult: Codable { let taskID: String; let status: String; let processCount: Int?; let resultURL: String? }
}
