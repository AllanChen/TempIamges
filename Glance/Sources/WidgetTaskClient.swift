import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WidgetTaskPhase: String, Codable {
    case uploading, submitting, processing, downloading, completed, failed, interrupted
    var isActive: Bool { [.uploading, .submitting, .processing, .downloading].contains(self) }
}

final class WidgetTaskClient {
    static let shared = WidgetTaskClient()
    private let apiBase = URL(string: "https://glance-service.allanchanni.workers.dev/api/v2")!
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 40
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
    private let taskTokenKey = "glance.widgetTaskToken"
    private let freeimageKeyKey = "glance.freeimageAPIKey"

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let token = UserDefaults.standard.string(forKey: taskTokenKey)
            .flatMap { $0.isEmpty ? nil : $0 } ?? AuthManager.shared.session?.token
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

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
                self.fetchCountry { country in
                    self.submit(widgetID: widgetID, commandID: commandID, mediaURL: url, location: country) { submission in
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
    }

    func resume(taskID: String, progress: @escaping (WidgetTaskPhase, Int) -> Void,
                completion: @escaping (Result<URL, Error>) -> Void) {
        progress(.processing, 0)
        poll(taskID: taskID, started: Date(), progress: progress, completion: completion)
    }

    private func uploadIfNeeded(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        prepareLocalInput(url) { prepared in
            switch prepared {
            case .failure(let error): completion(.failure(error))
            case .success(let localURL):
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: localURL)
                        var request = self.authorizedRequest(self.apiBase.appendingPathComponent("uploads")); request.httpMethod = "POST"
                        let boundary = "Boundary-\(UUID().uuidString)"
                        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                        let mime = UTType(filenameExtension: localURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(localURL.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
                        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
                        self.upload(request, attempt: 0) { result in
                            switch result {
                            case .success:
                                completion(result)
                            case .failure(let cloudflareError):
                                guard let fallbackImage = Self.freeimageImage(data: data, mime: mime),
                                      let key = UserDefaults.standard.string(forKey: self.freeimageKeyKey),
                                      !key.isEmpty else {
                                    completion(.failure(cloudflareError))
                                    return
                                }
                                self.uploadToFreeimage(data: fallbackImage.data, mime: fallbackImage.mime, key: key) { fallback in
                                    switch fallback {
                                    case .success:
                                        completion(fallback)
                                    case .failure(let fallbackError):
                                        completion(.failure(WidgetUploadFallbackError(
                                            cloudflare: cloudflareError, freeimage: fallbackError)))
                                    }
                                }
                            }
                        }
                    } catch { completion(.failure(error)) }
                }
            }
        }
    }

    private func upload(_ request: URLRequest, attempt: Int,
                        completion: @escaping (Result<String, Error>) -> Void) {
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error = error as NSError?, error.domain == NSURLErrorDomain,
               [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet].contains(error.code),
               attempt < 2 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Double(attempt + 1)) {
                    self.upload(request, attempt: attempt + 1, completion: completion)
                }
                return
            }
            do {
                if let error { throw error }
                let envelope: UploadEnvelope = try Self.decode(data, response)
                guard envelope.success, let value = envelope.result?.url else { throw WidgetError.unavailable }
                completion(.success(value))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    private static let freeimageMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp"
    ]

    private static func freeimageImage(data: Data, mime: String) -> (data: Data, mime: String)? {
        if freeimageMIMETypes.contains(mime) { return (data, mime) }
        guard mime == "image/heic" || mime == "image/heif",
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, "image/png")
    }

    private func uploadToFreeimage(data: Data, mime: String, key: String,
                                   completion: @escaping (Result<String, Error>) -> Void) {
        let boundary = "FreeimageBoundary-\(UUID().uuidString)"
        let fileExtension = mime == "image/jpeg" ? "jpg" : String(mime.split(separator: "/").last ?? "png")
        var body = Data()
        for (name, value) in [("key", key), ("action", "upload"), ("format", "json")] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"source\"; filename=\"widget-input.\(fileExtension)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: URL(string: "https://freeimage.host/api/1/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                guard let data, let http = response as? HTTPURLResponse else { throw WidgetError.unavailable }
                guard (200..<300).contains(http.statusCode),
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["status_code"] as? Int == 200,
                      let image = payload["image"] as? [String: Any],
                      let rawURL = image["url"] as? String,
                      let url = URL(string: rawURL), url.scheme == "https",
                      let host = url.host?.lowercased(),
                      host == "iili.io" || host.hasSuffix(".iili.io") || host == "freeimage.host" else {
                    throw WidgetTaskRequestError(statusCode: http.statusCode, message: "Freeimage upload failed.")
                }
                completion(.success(url.absoluteString))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    /// Materialize clipboard images and remote image URLs in the user's local
    /// Glance folder before uploading them to the Worker. URLSession keeps both
    /// the remote download and the subsequent upload off the main thread.
    private func prepareLocalInput(_ url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        if url.isFileURL {
            let clipboardPrefix = FileManager.default.temporaryDirectory
                .appendingPathComponent("GlanceClipboard", isDirectory: true).standardizedFileURL.path
            if url.standardizedFileURL.path.hasPrefix(clipboardPrefix + "/") {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let destination = try self.localInputURL(for: url)
                        try FileManager.default.copyItem(at: url, to: destination)
                        completion(.success(destination))
                    } catch { completion(.failure(error)) }
                }
            } else {
                completion(.success(url))
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Glance/2.0", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request) { [weak self] temporary, response, error in
            guard let self else { return }
            do {
                if let error { throw error }
                guard let temporary else { throw WidgetError.unavailable }
                let destination = try self.localInputURL(for: url, response: response)
                try FileManager.default.moveItem(at: temporary, to: destination)
                completion(.success(destination))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    private func localInputURL(for source: URL, response: URLResponse? = nil) throws -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Glance", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let responseExtension = response?.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension }
        let ext = (responseExtension?.isEmpty == false ? responseExtension! : source.pathExtension)
        let safeExtension = ext.isEmpty ? "bin" : ext
        return folder.appendingPathComponent("input-\(UUID().uuidString).\(safeExtension)")
    }

    private func fetchCountry(completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://ipapi.co/country/")!)
        request.timeoutInterval = 5
        session.dataTask(with: request) { [weak self] data, response, error in
            if error == nil, let data, let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               code.count == 2, code.allSatisfy({ $0 >= "A" && $0 <= "Z" }), code != "XX" {
                completion(code)
            } else {
                self?.fetchCloudflareCountry(completion: completion)
            }
        }.resume()
    }

    private func fetchCloudflareCountry(completion: @escaping (String) -> Void) {
        var request = authorizedRequest(apiBase.appendingPathComponent("location"))
        request.timeoutInterval = 5
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let envelope = try? JSONDecoder().decode(LocationEnvelope.self, from: data),
                  envelope.success, !envelope.result.location.isEmpty else {
                completion("Unknown")
                return
            }
            completion(envelope.result.location)
        }.resume()
    }

    private func submit(widgetID: String, commandID: String, mediaURL: String, location: String,
                        completion: @escaping (Result<String, Error>) -> Void) {
        var request = authorizedRequest(apiBase.appendingPathComponent("tasks")); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "widgetID": widgetID,
            "commandID": commandID,
            "taskParams": ["url": mediaURL, "prompt": "", "mask": NSNull(), "location": location]
        ])
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
        let request = authorizedRequest(apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let result = envelope.result else { throw WidgetError.unavailable }
                if (result.status == "completed" || result.status == "succeeded"), let raw = result.resultURL, let url = URL(string: raw) { completion(.success(url)); return }
                if result.status == "failed" { completion(.failure(WidgetError.unavailable)); return }
                progress(.processing, result.processCount ?? 0)
            } catch { /* transient query errors retry until the overall timeout */ }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { self.poll(taskID: taskID, started: started, progress: progress, completion: completion) }
        }.resume()
    }

    private static func decode<T: Decodable>(_ data: Data?, _ response: URLResponse?) throws -> T {
        guard let data, let http = response as? HTTPURLResponse else { throw WidgetError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let failure = payload?["error"] as? [String: Any]
            throw WidgetTaskRequestError(statusCode: http.statusCode, message: failure?["message"] as? String)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private struct UploadEnvelope: Codable { let success: Bool; let result: UploadResult? }
    private struct UploadResult: Codable { let url: String }
    private struct LocationEnvelope: Codable { let success: Bool; let result: LocationResult }
    private struct LocationResult: Codable { let location: String }
    private struct TaskEnvelope: Codable { let success: Bool; let result: TaskResult? }
    private struct TaskResult: Codable { let taskID: String; let status: String; let processCount: Int?; let resultURL: String? }
}

private struct WidgetTaskRequestError: LocalizedError {
    let statusCode: Int
    let message: String?

    var errorDescription: String? {
        message ?? "Widget request failed (HTTP \(statusCode))."
    }
}

private struct WidgetUploadFallbackError: LocalizedError {
    let cloudflare: Error
    let freeimage: Error

    var errorDescription: String? {
        "Cloudflare upload failed: \(cloudflare.localizedDescription) Freeimage upload failed: \(freeimage.localizedDescription)"
    }
}
