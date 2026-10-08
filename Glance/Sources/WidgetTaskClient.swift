import Foundation
import CFNetwork
import ImageIO
import UniformTypeIdentifiers

enum WidgetTaskPhase: String, Codable {
    case uploading, submitting, processing, downloading, completed, failed, interrupted
    var isActive: Bool { [.uploading, .submitting, .processing, .downloading].contains(self) }
}

final class WidgetTaskClient {
    static let shared = WidgetTaskClient()
    private let apiBase = URL(string: "https://api.glance.mcreator.ai/api/v2")!
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 40
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()
    private let directAPISession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 40
        configuration.timeoutIntervalForResource = 180
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
            kCFNetworkProxiesProxyAutoConfigEnable as String: 0
        ]
        return URLSession(configuration: configuration)
    }()
    private let freeimageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()
    private let taskTokenKey = "glance.widgetTaskToken"

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let token = UserDefaults.standard.string(forKey: taskTokenKey)
            .flatMap { $0.isEmpty ? nil : $0 } ?? AuthManager.shared.session?.token
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Prefer the local network for the Glance API so a system proxy cannot
    /// change the detected country. Fall back to the user's proxy when direct
    /// access is unavailable.
    private func apiDataTask(with request: URLRequest,
                             completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        directAPISession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let issue = error as NSError?, issue.domain == NSURLErrorDomain {
                Logger.warning("Direct Glance API request failed; trying system network: \(issue.localizedDescription)")
                self.session.dataTask(with: request, completionHandler: completion).resume()
            } else {
                completion(data, response, error)
            }
        }.resume()
    }

    func run(widgetID: String, commandID: String, mediaURL: URL,
             progress: @escaping (WidgetTaskPhase, Int) -> Void,
             submitted: @escaping (String) -> Void,
             completion: @escaping (Result<URL, Error>) -> Void) {
        progress(.uploading, 0)
        fetchCountry { [weak self] country in
            guard let self else { return }
            self.fetchUploadConfig { config in
                self.uploadIfNeeded(mediaURL, country: country, config: config) { upload in
                    switch upload {
                    case .failure(let error): completion(.failure(error))
                    case .success(let url):
                        progress(.submitting, 0)
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
    }

    func resume(taskID: String, progress: @escaping (WidgetTaskPhase, Int) -> Void,
                completion: @escaping (Result<URL, Error>) -> Void) {
        progress(.processing, 0)
        poll(taskID: taskID, started: Date(), progress: progress, completion: completion)
    }

    /// Fetch a fresh URL when the user copies a result. Glance R2 asset links
    /// are signed for one hour and are renewed by the task status endpoint.
    func fetchResultURL(taskID: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let request = authorizedRequest(apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        apiDataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let result = envelope.result,
                      result.status == "completed" || result.status == "succeeded",
                      let raw = result.result?.first?.url ?? result.resultURL,
                      let url = URL(string: raw), url.scheme == "https" else {
                    throw WidgetError.unavailable
                }
                completion(.success(url))
            } catch { completion(.failure(error)) }
        }
    }

    private func fetchUploadConfig(completion: @escaping (UploadConfig) -> Void) {
        var request = authorizedRequest(apiBase.appendingPathComponent("glance_config"))
        request.timeoutInterval = 5
        apiDataTask(with: request) { data, response, error in
            guard error == nil, let data, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let envelope = try? JSONDecoder().decode(UploadConfigEnvelope.self, from: data),
                  envelope.success, let config = envelope.result else {
                Logger.warning("Widget upload config unavailable; using R2")
                completion(UploadConfig(locationBasedUpload: false, freeimageKey: nil))
                return
            }
            completion(config)
        }
    }

    private func uploadIfNeeded(_ url: URL, country: String, config: UploadConfig,
                                completion: @escaping (Result<String, Error>) -> Void) {
        prepareLocalInput(url) { prepared in
            switch prepared {
            case .failure(let error): completion(.failure(error))
            case .success(let localURL):
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: localURL)
                        let mime = UTType(filenameExtension: localURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        let uploadToR2 = {
                            self.uploadToService(data: data, mime: mime, filename: localURL.lastPathComponent,
                                                 completion: completion)
                        }
                        let china = ["CN", "CHINA"].contains(country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                        let key = config.freeimageKey?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard config.locationBasedUpload, china, mime.hasPrefix("image/") else {
                            Logger.info("Widget upload using R2 (country: \(country), location routing: \(config.locationBasedUpload))")
                            uploadToR2()
                            return
                        }
                        guard let key, !key.isEmpty else {
                            Logger.warning("Freeimage API key missing from config; falling back to R2")
                            uploadToR2()
                            return
                        }
                        guard let image = Self.freeimageImage(data: data, mime: mime) else {
                            Logger.warning("Image cannot be prepared for Freeimage; falling back to R2")
                            uploadToR2()
                            return
                        }
                        Logger.info("Widget upload using Freeimage (country: \(country))")
                        self.uploadToFreeimage(data: image.data, mime: image.mime, key: key) { result in
                            switch result {
                            case .success:
                                Logger.info("Widget upload completed via Freeimage")
                                completion(result)
                            case .failure(let error):
                                Logger.warning("Freeimage upload failed; falling back to R2: \(error.localizedDescription)")
                                uploadToR2()
                            }
                        }
                    } catch { completion(.failure(error)) }
                }
            }
        }
    }

    private func uploadToService(data: Data, mime: String, filename: String,
                                 completion: @escaping (Result<String, Error>) -> Void) {
        var request = authorizedRequest(apiBase.appendingPathComponent("uploads"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        upload(request, attempt: 0, completion: completion)
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
        let boundary = "FreeimageBoundary-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
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
        freeimageSession.dataTask(with: request) { data, response, error in
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

    private func upload(_ request: URLRequest, attempt: Int,
                        completion: @escaping (Result<String, Error>) -> Void) {
        apiDataTask(with: request) { [weak self] data, response, error in
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
                Logger.info("Widget upload completed via R2")
                completion(.success(value))
            } catch {
                Logger.warning("R2 upload failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
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
        var request = authorizedRequest(apiBase.appendingPathComponent("location"))
        request.timeoutInterval = 5
        apiDataTask(with: request) { [weak self] data, response, error in
            if error == nil, let data, let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let envelope = try? JSONDecoder().decode(LocationEnvelope.self, from: data),
               envelope.success, !envelope.result.location.isEmpty,
               envelope.result.location != "Unknown" {
                completion(envelope.result.location)
            } else {
                Logger.warning("GlanceService location unavailable; trying ipapi")
                self?.fetchIPAPICountry(completion: completion)
            }
        }
    }

    private func fetchIPAPICountry(completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://ipapi.co/country/")!)
        request.timeoutInterval = 5
        session.dataTask(with: request) { data, response, error in
            if error == nil, let data, let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               code.count == 2, code.allSatisfy({ $0 >= "A" && $0 <= "Z" }), code != "XX" {
                completion(code)
            } else {
                Logger.warning("Country lookup unavailable; using R2")
                completion("Unknown")
            }
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
        apiDataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let taskID = envelope.result?.taskID else { throw WidgetError.unavailable }
                completion(.success(taskID))
            } catch { completion(.failure(error)) }
        }
    }

    private func poll(taskID: String, started: Date,
                      progress: @escaping (WidgetTaskPhase, Int) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void) {
        guard Date().timeIntervalSince(started) <= 1800 else { completion(.failure(WidgetError.unavailable)); return }
        let request = authorizedRequest(apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        apiDataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let result = envelope.result else { throw WidgetError.unavailable }
                if result.status == "completed" || result.status == "succeeded" {
                    if let artifacts = result.result, !artifacts.isEmpty {
                        self.prepareResults(artifacts, taskID: taskID, completion: completion)
                        return
                    }
                    if let raw = result.resultURL, let url = URL(string: raw) {
                        completion(.success(url)); return
                    }
                    completion(.failure(WidgetError.unavailable)); return
                }
                if result.status == "failed" {
                    completion(.failure(WidgetTaskExecutionError(message: result.error)))
                    return
                }
                progress(.processing, result.processCount ?? 0)
            } catch { /* transient query errors retry until the overall timeout */ }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { self.poll(taskID: taskID, started: started, progress: progress, completion: completion) }
        }
    }

    private func prepareResults(_ artifacts: [TaskArtifact], taskID: String,
                                completion: @escaping (Result<URL, Error>) -> Void) {
        if artifacts.count == 1, artifacts[0].type != "text",
           let raw = artifacts[0].url, let url = URL(string: raw) {
            completion(.success(url)); return
        }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Glance", isDirectory: true)
            .appendingPathComponent("\(taskID)-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { completion(.failure(error)); return }
        func save(_ index: Int) {
            if index >= artifacts.count {
                completion(.success(artifacts.count == 1 ? folder.appendingPathComponent("result.txt") : folder))
                return
            }
            let artifact = artifacts[index]
            if artifact.type == "text", let value = artifact.text {
                do {
                    try value.write(to: folder.appendingPathComponent(artifacts.count == 1 ? "result.txt" : "result-\(index + 1).txt"), atomically: true, encoding: .utf8)
                    save(index + 1)
                } catch { completion(.failure(error)) }
                return
            }
            guard let raw = artifact.url, let url = URL(string: raw) else {
                completion(.failure(WidgetError.unavailable)); return
            }
            self.session.downloadTask(with: url) { temporary, response, error in
                guard let temporary, error == nil else {
                    completion(.failure(error ?? WidgetError.unavailable)); return
                }
                do {
                    let mimeExtension = response?.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
                    let ext = mimeExtension ?? (artifact.type == "audio" ? "m4a" : artifact.type == "video" ? "mp4" : "png")
                    let destination = folder.appendingPathComponent("result-\(index + 1).\(ext)")
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    save(index + 1)
                } catch { completion(.failure(error)) }
            }.resume()
        }
        save(0)
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
    private struct UploadConfig: Codable { let locationBasedUpload: Bool; let freeimageKey: String? }
    private struct UploadConfigEnvelope: Codable { let success: Bool; let result: UploadConfig? }
    private struct LocationEnvelope: Codable { let success: Bool; let result: LocationResult }
    private struct LocationResult: Codable { let location: String }
    private struct TaskEnvelope: Codable { let success: Bool; let result: TaskResult? }
    private struct TaskResult: Codable {
        let taskID: String
        let status: String
        let processCount: Int?
        let resultURL: String?
        let result: [TaskArtifact]?
        let error: String?
    }
    private struct TaskArtifact: Codable { let type: String?; let text: String?; let url: String? }
}

private struct WidgetTaskExecutionError: LocalizedError {
    let message: String?

    var errorDescription: String? {
        let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? "The Widget task failed without reporting a reason." : detail
    }
}

private struct WidgetTaskRequestError: LocalizedError {
    let statusCode: Int
    let message: String?

    var errorDescription: String? {
        message ?? "Widget request failed (HTTP \(statusCode))."
    }
}
