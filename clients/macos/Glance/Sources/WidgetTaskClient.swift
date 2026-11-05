import AVFoundation
import CryptoKit
import Foundation
import CFNetwork
import ImageIO
import UniformTypeIdentifiers

enum WidgetTaskPhase: String, Codable {
    case uploading, submitting, processing, downloading, completed, failed, interrupted, cancelled, expired
    var isActive: Bool { [.uploading, .submitting, .processing, .downloading].contains(self) }
    /// Ended without a result and not because the user stopped it; shown as a failure.
    var isFailure: Bool { [.failed, .interrupted, .expired].contains(self) }
}

/// Lets the user stop a Widget task. The stages before submission and the
/// polling loop check it; the remote task is cancelled separately.
final class WidgetTaskCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Where a queued task stands; shown so the user knows how long to wait.
struct WidgetTaskBilling {
    let taskID: String
    let status: String
    let creditCost: Int?
    let refundedCredits: Int?
    let balance: Int?
    let deliveryRequired: Bool?
    let delivered: Bool?
}

struct WidgetQueueInfo: Equatable {
    let position: Int
    let estimatedWaitSeconds: Int?
}

/// The service refused the task because its queue is full (HTTP 429 queue_full).
struct WidgetServiceBusyError: LocalizedError {
    var errorDescription: String? { "The service is busy right now. Please try again later.".localized }
}

struct WidgetTaskCancelledError: LocalizedError {
    var errorDescription: String? { "Cancelled".localized }
}

/// The task waited too long in the queue and the service gave up on it.
struct WidgetTaskExpiredError: LocalizedError {
    var errorDescription: String? { "The task timed out. Its credits will be refunded automatically. Please try again.".localized }
}

struct WidgetVideoEvidence: Codable, Equatable {
    let durationSeconds: Double
    let byteSize: Int
    let sha256: String

    var dictionary: [String: Any] {
        ["durationSeconds": durationSeconds, "byteSize": byteSize, "sha256": sha256]
    }
    static func inspect(_ url: URL, completion: @escaping (Result<Self, Error>) -> Void) {
        // No upload, processing, or main-thread disk access during preflight.
        guard url.isFileURL else {
            completion(.failure(AuthError.message("Save this video locally before checking its duration and price.".localized)))
            return
        }
        Task {
            do {
                let evidence = try await read(url)
                await MainActor.run { completion(.success(evidence)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
    private static func read(_ url: URL) async throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 50 * 1024 * 1024 else {
            throw AuthError.message("Video must be nonempty and at most 50 MiB. Compress it and try again.".localized)
        }
        var seconds: Double = 0
        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.load(.tracks),
           let video = tracks.first(where: { $0.mediaType == .video }),
           let range = try? await video.load(.timeRange) {
            seconds = range.duration.seconds
        }
        if !seconds.isFinite || seconds <= 0 { seconds = probeDuration(url) }
        guard seconds.isFinite, seconds > 0 else {
            throw AuthError.message("Cannot read this video's duration. Save it as MP4 and try again.".localized)
        }
        let segments = ceil(seconds / (seconds <= 8 ? 8 : 7.8))
        guard segments <= 24 else {
            throw AuthError.message("This video is too long. Trim it to 187.2 seconds or less before submitting. Nothing has been charged.".localized)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            bytes += chunk.count
            guard bytes <= 50 * 1024 * 1024 else { throw AuthError.message("The video changed. Check its price again.".localized) }
            hash.update(data: chunk)
        }
        guard bytes == size else { throw AuthError.message("The video changed. Check its price again.".localized) }
        return Self(durationSeconds: seconds, byteSize: size, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private static func probeDuration(_ url: URL) -> Double {
        let candidates = [Bundle.main.url(forResource: "ffprobe", withExtension: nil),
                          URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"),
                          URL(fileURLWithPath: "/usr/local/bin/ffprobe")].compactMap { $0 }
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return 0 }
        let process = Process(), pipe = Pipe()
        process.executableURL = binary
        process.arguments = ["-v", "error", "-select_streams", "v:0", "-show_entries", "format=duration:stream=duration", "-of", "json", url.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return 0 }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stream = (object["streams"] as? [[String: Any]])?.first else { return 0 }
        let raw = stream["duration"] as? String
        let format = object["format"] as? [String: Any]
        return Double((raw == nil || raw == "N/A" ? format?["duration"] as? String : raw) ?? "") ?? 0
    }
}

struct WidgetTaskQuote: Codable {
    let quoteID: String
    let mode: String
    let unitSeconds: Int
    let unitPrice: Int
    let units: Int
    let totalCredits: Int
    let expiresAt: String
    let balance: Int
    let shortfall: Int
    let evidence: WidgetVideoEvidence?
    var preparedVideoURL: URL? = nil
    var billingIntentID: String? = nil
    var topupOrderID: String? = nil

    var detail: String {
        if let evidence {
            return String(format: "%.3f seconds · %d × %d credits / 10 seconds".localized,
                          evidence.durationSeconds, units, unitPrice)
        }
        return String(format: "%d credits / task".localized, totalCredits)
    }
}

final class WidgetTaskClient {
    static let shared = WidgetTaskClient()
    private let apiBase = URL(string: "https://api.glancepreview.com/api/v2")!
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
    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // Uploads and tasks must use the same account session as billing.
        // Legacy debug tokens are not accepted by the account-backed API.
        if let token = AuthManager.shared.session?.token {
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
             mediaKind: MediaInfo.Kind,
             input: WidgetTaskInput? = nil,
             requestKey: String = UUID().uuidString,
             quote: WidgetTaskQuote? = nil,
             evidenceChecked: Bool = false,
             billing: @escaping (WidgetTaskBilling) -> Void = { _ in },
             cancellation: WidgetTaskCancellation? = nil,
             progress: @escaping (WidgetTaskPhase, Int) -> Void,
             queue: @escaping (WidgetQueueInfo?) -> Void = { _ in },
             submitted: @escaping (String) -> Void,
             completion: @escaping (Result<URL, Error>) -> Void) {
        guard let ownerID = AuthManager.shared.session?.user.id else {
            completion(.failure(WidgetTaskRequestError(statusCode: 401, message: nil)))
            return
        }
        let mediaURLs = quote?.preparedVideoURL.map { [$0] } ?? input?.mediaURLs ?? [mediaURL]
        guard (1...4).contains(mediaURLs.count) else {
            completion(.failure(WidgetTaskInputError.invalidImageCount))
            return
        }
        if let expected = quote?.evidence, !evidenceChecked {
            guard mediaURLs.count == 1 else { completion(.failure(AuthError.message("Select one video per task.".localized))); return }
            WidgetVideoEvidence.inspect(mediaURLs[0]) { result in
                guard AuthManager.shared.session?.user.id == ownerID else {
                    completion(.failure(WidgetTaskRequestError(statusCode: 401, message: nil))); return
                }
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let actual):
                    guard actual == expected else {
                        completion(.failure(WidgetTaskRequestError(statusCode: 409, message: "The video changed. Check its price again.".localized, code: "input_changed")))
                        return
                    }
                    self.run(widgetID: widgetID, commandID: commandID, mediaURL: mediaURL,
                             mediaKind: mediaKind, input: input, requestKey: requestKey, quote: quote,
                             evidenceChecked: true, billing: billing, cancellation: cancellation,
                             progress: progress, queue: queue, submitted: submitted, completion: completion)
                }
            }
            return
        }
        if cancellation?.isCancelled == true { completion(.failure(WidgetTaskCancelledError())); return }
        progress(.uploading, 0)
        fetchCountry { [weak self] country in
            guard let self else { return }
            self.fetchUploadConfig { config in
                guard AuthManager.shared.session?.user.id == ownerID else {
                    completion(.failure(WidgetTaskRequestError(statusCode: 401, message: nil))); return
                }
                if cancellation?.isCancelled == true { completion(.failure(WidgetTaskCancelledError())); return }
                self.uploadMedia(mediaURLs, country: country, config: config) { upload in
                    switch upload {
                    case .failure(let error): completion(.failure(error))
                    case .success(let urls):
                        if cancellation?.isCancelled == true { completion(.failure(WidgetTaskCancelledError())); return }
                        let submitTask: (String?) -> Void = { mask in
                            guard AuthManager.shared.session?.user.id == ownerID else {
                                completion(.failure(WidgetTaskRequestError(statusCode: 401, message: nil))); return
                            }
                            progress(.submitting, 0)
                            self.submit(widgetID: widgetID, commandID: commandID,
                                        mediaURLs: urls, prompt: input?.prompt,
                                        maskURL: mask,
                                        usesMultipleImages: input?.usesMultipleImages == true,
                                        usesMultipleVideos: input?.usesMultipleVideos == true,
                                        mediaType: mediaKind == .video ? "video" : "image",
                                        location: country, requestKey: requestKey, quote: quote) { submission in
                                switch submission {
                                case .failure(let error): completion(.failure(error))
                                case .success(let accepted):
                                    let taskID = accepted.taskID
                                    submitted(taskID)
                                    billing(accepted.billing)
                                    queue(accepted.queue)
                                    if cancellation?.isCancelled == true {
                                        // Cancelled while the submit request was in flight.
                                        self.cancel(taskID: taskID)
                                        completion(.failure(WidgetTaskCancelledError())); return
                                    }
                                    progress(.processing, 0)
                                    self.poll(taskID: taskID, started: Date(), cancellation: cancellation,
                                              progress: progress, queue: queue, billing: billing, completion: completion)
                                }
                            }
                        }
                        guard let maskURL = input?.maskURL else { submitTask(nil); return }
                        self.uploadIfNeeded(maskURL, country: country, config: config) { mask in
                            switch mask {
                            case .failure(let error): completion(.failure(error))
                            case .success(let url): submitTask(url)
                            }
                        }
                    }
                }
            }
        }
    }

    private func uploadMedia(_ urls: [URL], country: String, config: UploadConfig,
                             completion: @escaping (Result<[String], Error>) -> Void) {
        func next(_ index: Int, _ uploaded: [String]) {
            guard index < urls.count else { completion(.success(uploaded)); return }
            uploadIfNeeded(urls[index], country: country, config: config) { result in
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let url): next(index + 1, uploaded + [url])
                }
            }
        }
        next(0, [])
    }

    func resume(taskID: String, cancellation: WidgetTaskCancellation? = nil,
                progress: @escaping (WidgetTaskPhase, Int) -> Void,
                queue: @escaping (WidgetQueueInfo?) -> Void = { _ in },
                billing: @escaping (WidgetTaskBilling) -> Void = { _ in },
                completion: @escaping (Result<URL, Error>) -> Void) {
        progress(.processing, 0)
        poll(taskID: taskID, started: Date(), cancellation: cancellation, progress: progress, queue: queue, billing: billing, completion: completion)
    }

    /// Asks the service to cancel a queued or running task. Best effort: a task
    /// that already finished (or is unknown) simply stays as it is.
    func cancel(taskID: String) {
        var request = authorizedRequest(apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        request.httpMethod = "DELETE"
        apiDataTask(with: request) { _, response, error in
            if let error { Logger.warning("Widget task cancel request failed: \(error.localizedDescription)") }
            else if let http = response as? HTTPURLResponse { Logger.info("Widget task cancel answered HTTP \(http.statusCode)") }
        }
    }

    func settle(taskID: String?, requestKey: String?, outcome: String,
                completion: @escaping (Result<WidgetTaskBilling, Error>) -> Void) {
        let url: URL
        if outcome == "failed", let requestKey {
            url = apiBase.appendingPathComponent("task-requests").appendingPathComponent(requestKey).appendingPathComponent("abandon")
        } else if let taskID {
            url = apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID).appendingPathComponent("settle")
        } else { completion(.failure(WidgetError.unavailable)); return }
        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["outcome": outcome])
        apiDataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard let result = envelope.result, envelope.success else { throw WidgetError.unavailable }
                completion(.success(result.billing))
            } catch { completion(.failure(error)) }
        }
    }

    func fetchBilling(taskID: String, completion: @escaping (Result<WidgetTaskBilling, Error>) -> Void) {
        let request = authorizedRequest(apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        apiDataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard let result = envelope.result, envelope.success else { throw WidgetError.unavailable }
                completion(.success(result.billing))
            } catch { completion(.failure(error)) }
        }
    }

    /// Reject HTTP error pages and empty/non-media downloads before confirming delivery.
    static func validateDownload(_ file: URL, response: URLResponse?, allowedTypes: [String]?) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw WidgetTaskExecutionError(message: "The result could not be downloaded. Please check your connection and try again.".localized)
        }
        let mime = http.mimeType?.lowercased() ?? ""
        if mime.contains("html") || mime.contains("json") { throw WidgetError.unavailable }
        let types = allowedTypes ?? ["image", "video", "audio"]
        if types == ["image"] {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(source) > 0,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw WidgetError.unavailable }
        } else if !types.contains(where: { mime.hasPrefix($0 + "/") }) && mime != "application/octet-stream" {
            throw WidgetError.unavailable
        }
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
                    throw WidgetTaskRequestError(statusCode: http.statusCode, message: "Freeimage upload failed.".localized)
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
    func prepareLocalInput(_ url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
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

    private func submit(widgetID: String, commandID: String, mediaURLs: [String],
                        prompt: String?, maskURL: String?, usesMultipleImages: Bool,
                        usesMultipleVideos: Bool, mediaType: String,
                        location: String, requestKey: String, quote: WidgetTaskQuote?,
                        completion: @escaping (Result<AcceptedTask, Error>) -> Void) {
        guard let primaryURL = mediaURLs.first else {
            completion(.failure(WidgetTaskInputError.invalidImageCount))
            return
        }
        var request = authorizedRequest(apiBase.appendingPathComponent("tasks")); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestKey, forHTTPHeaderField: "Idempotency-Key")
        var taskParams: [String: Any] = [
            "url": primaryURL,
            "prompt": prompt ?? "",
            "mask": maskURL.map { $0 as Any } ?? NSNull(),
            "location": location
        ]
        var taskInput: [String: Any] = ["url": primaryURL, "type": mediaType]
        if usesMultipleVideos {
            taskParams["videos"] = mediaURLs
            taskInput["videos"] = mediaURLs
        } else if usesMultipleImages || mediaURLs.count > 1 {
            taskParams["images"] = mediaURLs
            taskInput["images"] = mediaURLs
        }
        var payload: [String: Any] = [
            "widgetID": widgetID,
            "deliveryRequired": true,
            "commandID": commandID,
            "input": taskInput,
            "taskParams": taskParams
        ]
        if let quote {
            payload["quoteID"] = quote.quoteID
            payload["expectedCreditCost"] = quote.totalCredits
            if let intent = quote.billingIntentID { payload["billingIntentID"] = intent }
            if let order = quote.topupOrderID { payload["topupOrderID"] = order }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        apiDataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let result = envelope.result else { throw WidgetError.unavailable }
                completion(.success(AcceptedTask(taskID: result.taskID, queue: result.queueInfo, billing: result.billing)))
            } catch let failure as WidgetTaskRequestError where failure.statusCode == 429 {
                completion(.failure(WidgetServiceBusyError()))
            } catch let failure as WidgetTaskRequestError
                        where failure.code == "widget_unavailable" || failure.code == "widget_not_found" {
                // Taken down after this client last synced: hide it everywhere now.
                DispatchQueue.main.async { WidgetRegistry.shared.markDelisted(id: widgetID) }
                completion(.failure(WidgetUnavailableError()))
            } catch { completion(.failure(error)) }
        }
    }

    struct AcceptedTask { let taskID: String; let queue: WidgetQueueInfo?; let billing: WidgetTaskBilling }

    private func poll(taskID: String, started: Date, cancellation: WidgetTaskCancellation?,
                      progress: @escaping (WidgetTaskPhase, Int) -> Void,
                      queue: @escaping (WidgetQueueInfo?) -> Void,
                      billing: @escaping (WidgetTaskBilling) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void) {
        if cancellation?.isCancelled == true { completion(.failure(WidgetTaskCancelledError())); return }
        guard Date().timeIntervalSince(started) <= 1800 else {
            // Giving up locally must also stop the remote task; otherwise a
            // worker still runs it and bills for a result nobody will see.
            cancel(taskID: taskID)
            completion(.failure(WidgetTaskExpiredError())); return
        }
        let request = authorizedRequest(apiBase.appendingPathComponent("tasks").appendingPathComponent(taskID))
        apiDataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            var delay: TimeInterval = 5
            do {
                if let error { throw error }
                let envelope: TaskEnvelope = try Self.decode(data, response)
                guard envelope.success, let result = envelope.result else { throw WidgetError.unavailable }
                billing(result.billing)
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
                if result.status == "cancelled" { completion(.failure(WidgetTaskCancelledError())); return }
                if result.status == "expired" { completion(.failure(WidgetTaskExpiredError())); return }
                progress(.processing, result.progress ?? result.processCount ?? 0)
                queue(result.status == "queued" ? result.queueInfo : nil)
                // The service says how soon a change is likely; stay within sane bounds.
                if let suggested = result.pollAfterMs { delay = min(10, max(1, Double(suggested) / 1000)) }
            } catch let failure as WidgetTaskRequestError where failure.statusCode == 401 || failure.statusCode == 404 {
                // Signed out or unknown task: retrying cannot help.
                completion(.failure(failure)); return
            } catch { /* transient query errors retry until the overall timeout */ }
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                self.poll(taskID: taskID, started: started, cancellation: cancellation,
                          progress: progress, queue: queue, billing: billing, completion: completion)
            }
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
                    try Self.validateDownload(temporary, response: response, allowedTypes: artifact.type.map { [$0] })
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
            throw WidgetTaskRequestError(statusCode: http.statusCode, message: failure?["message"] as? String,
                                         code: failure?["code"] as? String)
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
        let progress: Int?
        let pollAfterMs: Int?
        let queuePosition: Int?
        let estimatedWaitSeconds: Int?
        var queueInfo: WidgetQueueInfo? {
            guard let queuePosition, queuePosition > 0 else { return nil }
            return WidgetQueueInfo(position: queuePosition, estimatedWaitSeconds: estimatedWaitSeconds)
        }
        let resultURL: String?
        let result: [TaskArtifact]?
        let error: String?
        let creditCost: Int?
        let refundedCredits: Int?
        let balance: Int?
        let deliveryRequired: Bool?
        let delivered: Bool?
        var billing: WidgetTaskBilling {
            WidgetTaskBilling(taskID: taskID, status: status, creditCost: creditCost,
                              refundedCredits: refundedCredits, balance: balance,
                              deliveryRequired: deliveryRequired, delivered: delivered)
        }
    }
    private struct TaskArtifact: Codable { let type: String?; let text: String?; let url: String? }
}


private enum WidgetTaskInputError: LocalizedError {
    case invalidImageCount

    var errorDescription: String? {
        "A Widget task needs between one and four media inputs.".localized
    }
}

private struct WidgetTaskExecutionError: LocalizedError {
    let message: String?

    var errorDescription: String? {
        let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ["billing_input_mismatch", "billing_not_verified"].contains(detail) {
            return "The video could not be verified against its quote. Review the refund status, then select the video and confirm its price again.".localized
        }
        return detail.isEmpty ? "The Widget task failed without reporting a reason.".localized : detail
    }
}

struct WidgetUnavailableError: LocalizedError {
    var errorDescription: String? { "This Widget is no longer available.".localized }
}

struct WidgetTaskRequestError: LocalizedError {
    let statusCode: Int
    let message: String?
    var code: String? = nil

    var errorDescription: String? {
        if statusCode == 401 {
            return "Please sign in to use Widgets.".localized
        }
        return message?.localized ?? String(format: "Widget request failed (HTTP %d).".localized, statusCode)
    }
}
