import AppKit
import Foundation
import UserNotifications
import UniformTypeIdentifiers

struct WidgetTaskInput: Codable {
    let mediaURLs: [URL]
    let prompt: String?
    let maskURL: URL?
    let usesMultipleImages: Bool?
    let usesMultipleVideos: Bool?

    init(mediaURLs: [URL], prompt: String?, maskURL: URL?,
         usesMultipleImages: Bool? = nil, usesMultipleVideos: Bool? = nil) {
        self.mediaURLs = mediaURLs
        self.prompt = prompt
        self.maskURL = maskURL
        self.usesMultipleImages = usesMultipleImages
        self.usesMultipleVideos = usesMultipleVideos
    }
}

struct WidgetTaskRecord: Codable, Identifiable {
    let id: UUID
    let widgetID: String
    let widgetName: String
    let commandID: String
    let commandName: String
    let outputTypes: [String]?
    let showResultURL: Bool?
    let sourceURL: String
    let sourceKind: String?
    let createdAt: Date
    var updatedAt: Date
    var remoteTaskID: String?
    var phase: WidgetTaskPhase
    var progress: Int
    var outputPath: String?
    var outputURLString: String?
    var errorMessage: String?
    var input: WidgetTaskInput?
    /// Set while the task waits in the service queue; cleared once a worker takes it.
    var queuePosition: Int?
    var estimatedWaitSeconds: Int?
    var source: URL? { URL(string: sourceURL) }
    var output: URL? { outputPath.map { URL(fileURLWithPath: $0) } }
    /// "Queued · 3 ahead · ~2 min" while the service has not handed the task to
    /// a worker yet; nil otherwise. Shared by the Task Center list and detail pane.
    var queueText: String? {
        guard phase == .processing, progress == 0, let position = queuePosition else { return nil }
        let ahead = max(0, position - 1)
        if let seconds = estimatedWaitSeconds, seconds > 0 {
            let wait = seconds < 60 ? "\(seconds)s" : "\(max(1, Int((Double(seconds) / 60).rounded()))) min"
            return String(format: "Queued · %d ahead · ~%@".localized, ahead, wait)
        }
        return String(format: "Queued · %d ahead".localized, ahead)
    }
    var copyableMediaResultURL: String? {
        // Older saved tasks have no output snapshot; use the installed command.
        let installedCommand = WidgetRegistry.shared.installed
            .first(where: { $0.id == widgetID })?
            .commands.first(where: { $0.id == commandID })
        let displaysURL = showResultURL ?? installedCommand?.showResultURL ?? false
        let outputsMedia = outputTypes?.contains(where: { $0 == "image" || $0 == "video" })
            ?? (installedCommand?.outputs.contains(where: { $0 == "image" || $0 == "video" }) ?? false)
        guard phase == .completed, outputsMedia, displaysURL,
              let rawURL = outputURLString,
              let parsed = URL(string: rawURL),
              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              parsed.host != nil else { return nil }
        return rawURL
    }
}

final class WidgetTaskManager {
    static let shared = WidgetTaskManager()
    static let didChange = Notification.Name("WidgetTaskManager.didChange")
    private(set) var records: [WidgetTaskRecord] = []
    private let ioQueue = DispatchQueue(label: "Glance.WidgetTasks.io")
    /// Cancellation handles of tasks started or resumed in this launch. Main thread only.
    private var cancellations: [UUID: WidgetTaskCancellation] = [:]

    private init() {
        load()
        DispatchQueue.main.async { [weak self] in self?.resumePendingTasks() }
    }

    var activeCount: Int { records.filter { $0.phase.isActive }.count }
    func activeRecords(for source: URL) -> [WidgetTaskRecord] { records.filter { $0.phase.isActive && $0.source?.taskKey == source.taskKey } }
    func latestRecord(for source: URL) -> WidgetTaskRecord? { records.first { $0.source?.taskKey == source.taskKey } }
    func completedRecord(for output: URL) -> WidgetTaskRecord? {
        records.first { record in
            guard record.phase == .completed, let result = record.output else { return false }
            return result.standardizedFileURL.path == output.standardizedFileURL.path
        }
    }

    /// Source of the finished Widget run that produced `output`, if any.
    func sourceURL(forResult output: URL) -> URL? { completedRecord(for: output)?.source }
    /// Outputs of finished Widget runs on `source`, newest first.
    func completedOutputs(for source: URL) -> [URL] {
        records.filter { $0.phase == .completed && $0.source?.taskKey == source.taskKey }.compactMap { $0.output }
    }
    func isSameMedia(_ a: URL, _ b: URL) -> Bool { a.taskKey == b.taskKey }

    @discardableResult
    func start(widget: WidgetManifest, command: WidgetCommand, media: MediaInfo,
               input: WidgetTaskInput? = nil) -> UUID? {
        let matching = records.filter { $0.phase.isActive && $0.source?.taskKey == media.url.taskKey && $0.widgetID == widget.id && $0.commandID == command.id }
        if !matching.isEmpty {
            // A task that never received a remote ID cannot be running. Older
            // clients could also leave a stale active record after a backend
            // migration; release the guard after a bounded recovery window.
            let stale = matching.filter { $0.remoteTaskID == nil || Date().timeIntervalSince($0.updatedAt) > 15 * 60 }
            for record in stale { update(record.id, phase: .interrupted, progress: 0, error: "Task was reset and can be submitted again.".localized) }
            if stale.count < matching.count { return nil }
        }
        let id = UUID()
        requestNotificationPermissionIfNeeded()
        // Names are display snapshots for the Task Center, taken in the app's language.
        let shownCommand = widget.localized(command)
        records.insert(WidgetTaskRecord(id: id, widgetID: widget.id, widgetName: widget.displayName,
            commandID: command.id, commandName: shownCommand.name, outputTypes: command.outputs,
            showResultURL: command.showResultURL,
            sourceURL: media.url.absoluteString,
            sourceKind: media.kind == .video ? "video" : "image",
            createdAt: Date(), updatedAt: Date(), remoteTaskID: nil, phase: .uploading,
            progress: 0, outputPath: nil, outputURLString: nil, errorMessage: nil,
            input: input), at: 0)
        changed()
        WidgetTaskClient.shared.run(widgetID: widget.id, commandID: command.id, mediaURL: media.url,
            mediaKind: media.kind,
            input: input,
            cancellation: makeCancellation(for: id),
            progress: { [weak self] phase, value in self?.update(id, phase: phase, progress: value) },
            queue: { [weak self] info in self?.setQueue(id, info) },
            submitted: { [weak self] remoteID in self?.setRemoteID(id, remoteID) },
            completion: { [weak self] result in self?.handleRemoteResult(id, result) })
        return id
    }

    func retry(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), let source = record.source,
              let widget = WidgetRegistry.shared.installed.first(where: { $0.id == record.widgetID }),
              let command = widget.commands.first(where: { $0.id == record.commandID }) else { return }
        if (record.phase == .failed || record.phase == .completed), record.outputURLString != nil,
           (record.output == nil || record.output.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true),
           let remoteID = record.remoteTaskID {
            update(id, phase: .processing, progress: 100)
            WidgetTaskClient.shared.resume(taskID: remoteID, cancellation: makeCancellation(for: id),
                progress: { [weak self] phase, value in self?.update(id, phase: phase, progress: value) },
                queue: { [weak self] info in self?.setQueue(id, info) },
                completion: { [weak self] result in self?.handleRemoteResult(id, result) })
            return
        }
        let kind: MediaInfo.Kind = record.sourceKind == "video" ||
            (record.sourceKind == nil && UTType(filenameExtension: source.pathExtension)?.conforms(to: .movie) == true)
            ? .video : .image
        _ = start(widget: widget, command: command,
                  media: MediaInfo(url: source, isLocal: source.isFileURL, kind: kind),
                  input: record.input)
    }

    /// Only before the result is being fetched: once it is downloading, finishing is quicker than stopping.
    func canCancel(_ record: WidgetTaskRecord) -> Bool {
        [.uploading, .submitting, .processing].contains(record.phase)
    }

    /// Stops a running task: the local polling stops at once and the service is
    /// asked to cancel it so a worker does not keep spending on it.
    func cancel(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), canCancel(record) else { return }
        cancellations[id]?.cancel()
        if let remoteID = record.remoteTaskID { WidgetTaskClient.shared.cancel(taskID: remoteID) }
        update(id, phase: .cancelled, progress: 0)
    }

    private func makeCancellation(for id: UUID) -> WidgetTaskCancellation {
        let cancellation = WidgetTaskCancellation()
        cancellations[id] = cancellation
        return cancellation
    }

    func remove(_ id: UUID) { records.removeAll { $0.id == id && !$0.phase.isActive }; changed() }
    func clear() { records.removeAll { !$0.phase.isActive }; changed() }

    /// Failed/interrupted state is session-local visual history. Remove it when
    /// the corresponding Image Inspect window closes so a later session does
    /// not keep a stale red filmstrip border around the source image.
    func clearFailed(for sources: [URL]) {
        let keys = Set(sources.map(\.taskKey))
        let originalCount = records.count
        records.removeAll { record in
            guard let source = record.source,
                  keys.contains(source.taskKey) else { return false }
            return record.phase.isFailure
        }
        if records.count != originalCount { changed() }
    }

    private func resumePendingTasks() {
        for record in records where record.phase.isActive {
            guard let remoteID = record.remoteTaskID else { update(record.id, phase: .interrupted, progress: 0); continue }
            WidgetTaskClient.shared.resume(taskID: remoteID, cancellation: makeCancellation(for: record.id),
                progress: { [weak self] phase, value in self?.update(record.id, phase: phase, progress: value) },
                queue: { [weak self] info in self?.setQueue(record.id, info) },
                completion: { [weak self] result in self?.handleRemoteResult(record.id, result) })
        }
    }

    private func handleRemoteResult(_ id: UUID, _ result: Result<URL, Error>) {
        DispatchQueue.main.async { [weak self] in self?.cancellations[id] = nil }
        switch result {
        case .failure(let error):
            switch error {
            case is WidgetTaskCancelledError: update(id, phase: .cancelled, progress: 0)
            case is WidgetTaskExpiredError: update(id, phase: .expired, progress: 0, error: error.localizedDescription)
            default: update(id, phase: .failed, progress: 0, error: error.localizedDescription)
            }
        case .success(let url):
            // The user stopped the task while its result was arriving: honour that.
            if records.first(where: { $0.id == id })?.phase == .cancelled { return }
            download(id, from: url)
        }
    }

    private func download(_ id: UUID, from url: URL) {
        if url.isFileURL {
            finish(id, output: url, remoteURL: nil)
            return
        }
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            self.records[index].outputURLString = url.absoluteString
            self.changed()
        }
        update(id, phase: .downloading, progress: 100)
        URLSession.shared.downloadTask(with: url) { [weak self] temporary, response, error in
            guard let self else { return }
            guard let temporary, error == nil else { self.update(id, phase: .failed, progress: 0, error: error?.localizedDescription); return }
            do {
                let destination = try self.destinationURL(for: id, response: response, fallback: url)
                try FileManager.default.moveItem(at: temporary, to: destination)
                self.finish(id, output: destination, remoteURL: url)
            } catch { self.update(id, phase: .failed, progress: 0, error: error.localizedDescription) }
        }.resume()
    }

    /// "<source name>.<command>" so a result is recognisable next to its source and
    /// two sources never collide on one command name; just the command when the
    /// source has no usable name.
    static func resultBaseName(source: URL?, commandName: String) -> String {
        func clean(_ value: String) -> String {
            value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        }
        let command = clean(commandName.isEmpty ? "Widget Result" : commandName)
        guard let source else { return command }
        let stem = clean(source.deletingPathExtension().lastPathComponent).trimmingCharacters(in: .whitespaces)
        return stem.isEmpty || stem == "-" ? command : "\(stem).\(command)"
    }

    private func destinationURL(for id: UUID, response: URLResponse?, fallback: URL) throws -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("Glance", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suggested = response?.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension }
        let mimeExtension = response?.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
        let ext = suggested?.isEmpty == false ? suggested! : (mimeExtension ?? (fallback.pathExtension.isEmpty ? "bin" : fallback.pathExtension))
        let record = records.first(where: { $0.id == id })
        let base = Self.resultBaseName(source: record?.source, commandName: record?.commandName ?? "Widget Result")
        var destination = folder.appendingPathComponent("\(base).\(ext)"); var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) { destination = folder.appendingPathComponent("\(base) \(suffix).\(ext)"); suffix += 1 }
        return destination
    }

    private func finish(_ id: UUID, output: URL, remoteURL: URL?) {
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }),
                  self.records[index].phase != .cancelled else { return }
            self.records[index].phase = .completed; self.records[index].progress = 100
            self.records[index].outputPath = output.path
            self.records[index].outputURLString = remoteURL?.absoluteString
            self.records[index].updatedAt = Date(); self.changed()
            let content = UNMutableNotificationContent(); content.title = "Widget completed".localized; content.body = output.lastPathComponent
            content.userInfo = ["recordID": id.uuidString]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined { center.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        }
    }

    private func setQueue(_ id: UUID, _ info: WidgetQueueInfo?) {
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            let record = self.records[index]
            if record.queuePosition == info?.position && record.estimatedWaitSeconds == info?.estimatedWaitSeconds { return }
            self.records[index].queuePosition = info?.position
            self.records[index].estimatedWaitSeconds = info?.estimatedWaitSeconds
            self.changed()
        }
    }
    private func setRemoteID(_ id: UUID, _ remoteID: String) { DispatchQueue.main.async { if let index = self.records.firstIndex(where: { $0.id == id }) { self.records[index].remoteTaskID = remoteID; self.changed() } } }
    private func update(_ id: UUID, phase: WidgetTaskPhase, progress: Int, error: String? = nil) { DispatchQueue.main.async { if let index = self.records.firstIndex(where: { $0.id == id }) { if self.records[index].phase == .cancelled && phase != .cancelled { return }; self.records[index].phase = phase; self.records[index].progress = progress; self.records[index].errorMessage = error; self.records[index].updatedAt = Date(); self.changed() } } }
    private func changed() { records = Array(records.prefix(200)); save(); NotificationCenter.default.post(name: Self.didChange, object: self) }

    private var storeURL: URL { let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Glance", isDirectory: true); try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder.appendingPathComponent("widget-tasks.json") }
    private func load() { guard let data = try? Data(contentsOf: storeURL) else { return }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; records = (try? decoder.decode([WidgetTaskRecord].self, from: data)) ?? [] }
    private func save() { let snapshot = records, url = storeURL; ioQueue.async { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted]; if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) } } }
}

private extension URL { var taskKey: String { isFileURL ? standardizedFileURL.path : absoluteString } }
