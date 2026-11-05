import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

/// Serves completed HLS segments over loopback as ffmpeg produces them. AVPlayer
/// needs HTTP for HLS and can begin once the first segments exist.
final class WebMStreamingFallback {
    private let source: URL
    private let ffmpeg: URL
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GlanceWebMStream-\(UUID().uuidString)", isDirectory: true)
    private let queue = DispatchQueue(label: "com.glance.webm-stream", qos: .userInitiated)
    private var listener: NWListener?
    private var process: Process?
    private var completion: ((URL?) -> Void)?
    private var stopped = false

    init(source: URL, ffmpeg: URL) {
        self.source = source
        self.ffmpeg = ffmpeg
    }

    func start(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.stopped else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port?.rawValue else {
                        self.deliver(nil)
                        return
                    }
                    self.beginTranscoding(port: port)
                case .failed(let error):
                    Logger.error("WebM streaming server failed: \(error.localizedDescription)")
                    self.deliver(nil)
                default: break
                }
            }
            listener.start(queue: queue)
        } catch {
            Logger.error("WebM streaming server failed: \(error.localizedDescription)")
            deliver(nil)
        }
    }

    func stop() {
        queue.async { [self] in
            guard !stopped else { return }
            stopped = true
            listener?.cancel()
            listener = nil
            if process?.isRunning == true { process?.terminate() }
            process = nil
            try? FileManager.default.removeItem(at: directory)
            completion = nil
        }
    }

    private func beginTranscoding(port: UInt16) {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-i", source.path,
            "-map", "0:v:0", "-map", "0:a?", "-sn",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "23",
            "-pix_fmt", "yuv420p", "-force_key_frames", "expr:gte(t,n_forced*1)",
            "-c:a", "aac", "-b:a", "128k",
            "-f", "hls", "-hls_time", "1", "-hls_list_size", "0",
            "-hls_playlist_type", "event",
            "-hls_flags", "temp_file+independent_segments",
            "-hls_segment_filename", directory.appendingPathComponent("segment_%05d.ts").path,
            directory.appendingPathComponent("index.m3u8").path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finishedProcess in
            let exitCode = finishedProcess.terminationStatus
            self?.queue.async { [weak self] in
                guard self?.stopped == false, exitCode != 0 else { return }
                Logger.error("WebM streaming conversion exited with code \(exitCode)")
            }
        }
        do {
            try process.run()
        } catch {
            Logger.error("WebM streaming conversion failed to start: \(error.localizedDescription)")
            deliver(nil)
            return
        }
        self.process = process
        let playlist = directory.appendingPathComponent("index.m3u8")
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak process] in
            let deadline = ProcessInfo.processInfo.systemUptime + 12
            while ProcessInfo.processInfo.systemUptime < deadline {
                if let contents = try? String(contentsOf: playlist, encoding: .utf8),
                   let segment = contents.split(separator: "\n").filter({ $0.hasPrefix("segment_") }).last,
                   (contents.components(separatedBy: "#EXTINF").count > 3 || contents.contains("#EXT-X-ENDLIST")),
                   FileManager.default.fileExists(atPath: self?.directory.appendingPathComponent(String(segment)).path ?? "") {
                    self?.queue.async { self?.deliver(URL(string: "http://127.0.0.1:\(port)/index.m3u8")) }
                    return
                }
                if process?.isRunning == false { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            self?.queue.async { self?.deliver(nil) }
        }
    }

    private func deliver(_ url: URL?) {
        guard !stopped, let completion else { return }
        self.completion = nil
        DispatchQueue.main.async { completion(url) }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first else {
                connection.cancel()
                return
            }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
                self.respond(connection, status: "405 Method Not Allowed", body: Data(), mime: "text/plain")
                return
            }
            let name = String(parts[1].split(separator: "?").first ?? "").dropFirst()
            let segmentNumber = name.hasPrefix("segment_") && name.hasSuffix(".ts")
                ? name.dropFirst(8).dropLast(3) : Substring()
            guard name == "index.m3u8" || (!segmentNumber.isEmpty && segmentNumber.allSatisfy(\.isNumber)) else {
                self.respond(connection, status: "404 Not Found", body: Data(), mime: "text/plain")
                return
            }
            let file = self.directory.appendingPathComponent(String(name))
            guard let body = try? Data(contentsOf: file) else {
                self.respond(connection, status: "404 Not Found", body: Data(), mime: "text/plain")
                return
            }
            self.respond(connection, status: "200 OK", body: body,
                         mime: name == "index.m3u8" ? "application/vnd.apple.mpegurl" : "video/mp2t",
                         headOnly: parts[0] == "HEAD")
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: Data,
                         mime: String, headOnly: Bool = false) {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        if !headOnly { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
