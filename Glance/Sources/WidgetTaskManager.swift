import AppKit
import Foundation
import UserNotifications

struct WidgetTaskRecord: Codable, Identifiable {
    let id: UUID
    let widgetID: String
    let widgetName: String
    let commandID: String
    let commandName: String
    let sourceURL: String
    let createdAt: Date
    var updatedAt: Date
    var remoteTaskID: String?
    var phase: WidgetTaskPhase
    var progress: Int
    var outputPath: String?
    var errorMessage: String?
    var source: URL? { URL(string: sourceURL) }
    var output: URL? { outputPath.map { URL(fileURLWithPath: $0) } }
}

final class WidgetTaskManager {
    static let shared = WidgetTaskManager()
    static let didChange = Notification.Name("WidgetTaskManager.didChange")
    private(set) var records: [WidgetTaskRecord] = []
    private let ioQueue = DispatchQueue(label: "Glance.WidgetTasks.io")

    private init() {
        load()
        DispatchQueue.main.async { [weak self] in self?.resumePendingTasks() }
    }

    var activeCount: Int { records.filter { $0.phase.isActive }.count }
    func activeRecords(for source: URL) -> [WidgetTaskRecord] { records.filter { $0.phase.isActive && $0.source?.taskKey == source.taskKey } }
    func latestRecord(for source: URL) -> WidgetTaskRecord? { records.first { $0.source?.taskKey == source.taskKey } }

    @discardableResult
    func start(widget: WidgetManifest, command: WidgetCommand, media: MediaInfo) -> UUID? {
        guard !records.contains(where: { $0.phase.isActive && $0.source?.taskKey == media.url.taskKey && $0.widgetID == widget.id && $0.commandID == command.id }) else { return nil }
        let id = UUID()
        requestNotificationPermissionIfNeeded()
        records.insert(WidgetTaskRecord(id: id, widgetID: widget.id, widgetName: widget.name,
            commandID: command.id, commandName: command.name, sourceURL: media.url.absoluteString,
            createdAt: Date(), updatedAt: Date(), remoteTaskID: nil, phase: .uploading,
            progress: 0, outputPath: nil, errorMessage: nil), at: 0)
        changed()
        WidgetTaskClient.shared.run(widgetID: widget.id, commandID: command.id, mediaURL: media.url,
            progress: { [weak self] phase, value in self?.update(id, phase: phase, progress: value) },
            submitted: { [weak self] remoteID in self?.setRemoteID(id, remoteID) },
            completion: { [weak self] result in self?.handleRemoteResult(id, result) })
        return id
    }

    func retry(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), let source = record.source,
              let widget = WidgetRegistry.shared.installed.first(where: { $0.id == record.widgetID }),
              let command = widget.commands.first(where: { $0.id == record.commandID }) else { return }
        if record.phase == .completed, record.output.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true,
           let remoteID = record.remoteTaskID {
            update(id, phase: .processing, progress: 100)
            WidgetTaskClient.shared.resume(taskID: remoteID,
                progress: { [weak self] phase, value in self?.update(id, phase: phase, progress: value) },
                completion: { [weak self] result in self?.handleRemoteResult(id, result) })
            return
        }
        let kind: MediaInfo.Kind = command.inputTypes.contains("video") ? .video : .image
        _ = start(widget: widget, command: command, media: MediaInfo(url: source, isLocal: source.isFileURL, kind: kind))
    }

    func remove(_ id: UUID) { records.removeAll { $0.id == id && !$0.phase.isActive }; changed() }
    func clear() { records.removeAll { !$0.phase.isActive }; changed() }

    private func resumePendingTasks() {
        for record in records where record.phase.isActive {
            guard let remoteID = record.remoteTaskID else { update(record.id, phase: .interrupted, progress: 0); continue }
            WidgetTaskClient.shared.resume(taskID: remoteID,
                progress: { [weak self] phase, value in self?.update(record.id, phase: phase, progress: value) },
                completion: { [weak self] result in self?.handleRemoteResult(record.id, result) })
        }
    }

    private func handleRemoteResult(_ id: UUID, _ result: Result<URL, Error>) {
        switch result {
        case .failure(let error): update(id, phase: .failed, progress: 0, error: error.localizedDescription)
        case .success(let url): download(id, from: url)
        }
    }

    private func download(_ id: UUID, from url: URL) {
        update(id, phase: .downloading, progress: 100)
        URLSession.shared.downloadTask(with: url) { [weak self] temporary, response, error in
            guard let self else { return }
            guard let temporary, error == nil else { self.update(id, phase: .failed, progress: 0, error: error?.localizedDescription); return }
            do {
                let destination = try self.destinationURL(for: id, response: response, fallback: url)
                try FileManager.default.moveItem(at: temporary, to: destination)
                self.finish(id, output: destination)
            } catch { self.update(id, phase: .failed, progress: 0, error: error.localizedDescription) }
        }.resume()
    }

    private func destinationURL(for id: UUID, response: URLResponse?, fallback: URL) throws -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("Glance", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suggested = response?.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension }
        let ext = suggested?.isEmpty == false ? suggested! : (fallback.pathExtension.isEmpty ? "png" : fallback.pathExtension)
        let rawName = records.first(where: { $0.id == id })?.commandName ?? "Widget Result"
        let base = rawName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var destination = folder.appendingPathComponent("\(base).\(ext)"); var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) { destination = folder.appendingPathComponent("\(base) \(suffix).\(ext)"); suffix += 1 }
        return destination
    }

    private func finish(_ id: UUID, output: URL) {
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            self.records[index].phase = .completed; self.records[index].progress = 100
            self.records[index].outputPath = output.path; self.records[index].updatedAt = Date(); self.changed()
            let content = UNMutableNotificationContent(); content.title = "Widget completed".localized; content.body = output.lastPathComponent
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined { center.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        }
    }

    private func setRemoteID(_ id: UUID, _ remoteID: String) { DispatchQueue.main.async { if let index = self.records.firstIndex(where: { $0.id == id }) { self.records[index].remoteTaskID = remoteID; self.changed() } } }
    private func update(_ id: UUID, phase: WidgetTaskPhase, progress: Int, error: String? = nil) { DispatchQueue.main.async { if let index = self.records.firstIndex(where: { $0.id == id }) { self.records[index].phase = phase; self.records[index].progress = progress; self.records[index].errorMessage = error; self.records[index].updatedAt = Date(); self.changed() } } }
    private func changed() { records = Array(records.prefix(200)); save(); NotificationCenter.default.post(name: Self.didChange, object: self) }

    private var storeURL: URL { let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Glance", isDirectory: true); try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder.appendingPathComponent("widget-tasks.json") }
    private func load() { guard let data = try? Data(contentsOf: storeURL) else { return }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; records = (try? decoder.decode([WidgetTaskRecord].self, from: data)) ?? [] }
    private func save() { let snapshot = records, url = storeURL; ioQueue.async { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted]; if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) } } }
}

private extension URL { var taskKey: String { isFileURL ? standardizedFileURL.path : absoluteString } }
