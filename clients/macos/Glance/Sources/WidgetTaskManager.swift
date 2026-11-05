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
    var quote: WidgetTaskQuote? = nil
    var creditCost: Int?
    var refundedCredits: Int?
    var requestKey: String?
    var ownerUserID: Int?
    /// Persisted until the server confirms the outcome (survives offline/restart).
    var settlementOutcome: String?
    var billingStatusText: String? {
        if settlementOutcome == "failed" { return "Refund confirmation pending".localized }
        if settlementOutcome == "delivered" { return "Confirming task result".localized }
        if let refunded = refundedCredits, refunded > 0 { return String(format: "Refunded %d credits".localized, refunded) }
        if let cost = creditCost, cost > 0 {
            if remoteTaskID == nil { return phase.isActive ? String(format: "Estimated %d credits".localized, cost) : "Not charged".localized }
            return String(format: "Charged %d credits".localized, cost)
        }
        return creditCost == 0 ? "Free of charge".localized : nil
    }
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
    private var settlementsInFlight = Set<UUID>()
    private var settlementRetries: [UUID: Int] = [:]
    private var authObserver: NSObjectProtocol?

    private init() {
        load()
        authObserver = NotificationCenter.default.addObserver(forName: .authDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.reconcilePendingSettlements()
        }
        DispatchQueue.main.async { [weak self] in self?.resumePendingTasks() }
    }

    private var preflightKeys = Set<String>()

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
               input: WidgetTaskInput? = nil, over parent: NSWindow? = nil,
               confirmedQuote: WidgetTaskQuote? = nil) -> UUID? {
        // A menu or input panel opened before the Widget was taken down must
        // not start a run the service will reject.
        guard WidgetRegistry.shared.isAvailable(id: widget.id) else {
            Logger.info("WidgetTaskManager: ignored run of unavailable Widget \(widget.id)")
            return nil
        }
        guard BillingCoordinator.shared.requireWidgetSignIn(over: parent ?? NSApp.keyWindow, freeWidget: widget.taskCreditCost == 0, completion: { [weak self, weak parent] in
            _ = self?.start(widget: widget, command: command, media: media, input: input, over: parent)
        }) else { return nil }
        let matching = records.filter { $0.phase.isActive && $0.source?.taskKey == media.url.taskKey && $0.widgetID == widget.id && $0.commandID == command.id }
        if !matching.isEmpty {
            // Uploading/submitting tasks legitimately have no remote ID yet.
            // Do not turn a second click into another independently billed task.
            let stale = matching.filter { Date().timeIntervalSince($0.updatedAt) > 30 * 60 }
            for record in stale { update(record.id, phase: .interrupted, progress: 0, error: "Task was reset and can be submitted again.".localized) }
            if stale.count < matching.count { return nil }
        }
        // Every Widget, including fixed-price image tools, must pass this gate.
        // Duration billing only changes the quote calculation, never eligibility.
        let preflightKey = "\(widget.id)|\(command.id)|\(media.url.absoluteString)"
        guard let quote = confirmedQuote else {
            guard preflightKeys.insert(preflightKey).inserted else { return nil }
            BillingCoordinator.shared.confirmWidgetTask(widget: widget, command: command,
                mediaURLs: input?.mediaURLs ?? [media.url], over: parent ?? NSApp.keyWindow) { [weak self, weak parent] quote in
                guard let self else { return }
                self.preflightKeys.remove(preflightKey)
                guard let quote else { return }
                _ = self.start(widget: widget, command: command, media: media, input: input,
                               over: parent, confirmedQuote: quote)
            }
            return nil
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
            input: input, quote: quote, creditCost: quote.totalCredits, requestKey: id.uuidString, ownerUserID: AuthManager.shared.session?.user.id), at: 0)
        changed()
        // Persist the request identity before any upload/submission can leave.
        save { [weak self] saved in
            guard let self, let record = self.records.first(where: { $0.id == id }), record.phase.isActive else { return }
            guard saved else {
                self.update(id, phase: .failed, progress: 0, error: "Could not save the task. Check available disk space and try again.".localized)
                return
            }
            WidgetTaskClient.shared.run(widgetID: widget.id, commandID: command.id, mediaURL: media.url,
                mediaKind: media.kind,
                input: input,
                requestKey: id.uuidString, quote: quote,
                billing: { [weak self] value in self?.receiveBilling(id, value) },
                cancellation: self.makeCancellation(for: id),
                progress: { [weak self] phase, value in self?.update(id, phase: phase, progress: value) },
                queue: { [weak self] info in self?.setQueue(id, info) },
                submitted: { [weak self] remoteID in self?.setRemoteID(id, remoteID) },
                completion: { [weak self, weak parent] result in
                    if case .failure(let error as WidgetTaskRequestError) = result,
                       ["insufficient_credits", "price_changed", "quote_expired", "input_changed"].contains(error.code ?? "") {
                        DispatchQueue.main.async {
                            guard let self, let index = self.records.firstIndex(where: { $0.id == id }),
                                  self.records[index].phase != .cancelled,
                                  self.records[index].ownerUserID == AuthManager.shared.session?.user.id else { return }
                            // These are definitive pre-creation rejections, not uncertain submissions.
                            self.records[index].phase = .failed
                            self.records[index].errorMessage = error.localizedDescription
                            self.records[index].requestKey = nil
                            self.changed()
                            _ = self.start(widget: widget, command: command, media: media, input: input, over: parent)
                        }
                    } else { self?.handleRemoteResult(id, result) }
                })
        }
        return id
    }

    func retry(_ id: UUID, over parent: NSWindow? = nil) {
        guard let record = records.first(where: { $0.id == id }), let source = record.source,
              let widget = WidgetRegistry.shared.available.first(where: { $0.id == record.widgetID }),
              let command = widget.commands.first(where: { $0.id == record.commandID }) else { return }
        guard BillingCoordinator.shared.requireWidgetSignIn(over: parent ?? NSApp.keyWindow, freeWidget: widget.taskCreditCost == 0, completion: { [weak self, weak parent] in
            self?.retry(id, over: parent)
        }) else { return }
        guard record.settlementOutcome == nil else { reconcileSettlement(id); return }
        if record.phase == .completed, (record.refundedCredits ?? 0) == 0, record.outputURLString != nil,
           (record.output == nil || record.output.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true),
           let remoteID = record.remoteTaskID {
            update(id, phase: .processing, progress: 100)
            WidgetTaskClient.shared.resume(taskID: remoteID, cancellation: makeCancellation(for: id),
                progress: { [weak self] phase, value in self?.update(id, phase: phase, progress: value) },
                queue: { [weak self] info in self?.setQueue(id, info) },
                billing: { [weak self] value in self?.receiveBilling(id, value) },
                completion: { [weak self] result in self?.handleRemoteResult(id, result) })
            return
        }
        let kind: MediaInfo.Kind = record.sourceKind == "video" ||
            (record.sourceKind == nil && UTType(filenameExtension: source.pathExtension)?.conforms(to: .movie) == true)
            ? .video : .image
        _ = start(widget: widget, command: command,
                  media: MediaInfo(url: source, isLocal: source.isFileURL, kind: kind),
                  input: record.input, over: parent)
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

    func remove(_ id: UUID) { records.removeAll { $0.id == id && !$0.phase.isActive && $0.settlementOutcome == nil }; changed() }
    func clear() { records.removeAll { !$0.phase.isActive && $0.settlementOutcome == nil }; changed() }

    /// Failed/interrupted state is session-local visual history. Remove it when
    /// the corresponding Image Inspect window closes so a later session does
    /// not keep a stale red filmstrip border around the source image.
    func clearFailed(for sources: [URL]) {
        let keys = Set(sources.map(\.taskKey))
        let originalCount = records.count
        records.removeAll { record in
            guard let source = record.source,
                  keys.contains(source.taskKey) else { return false }
            return record.phase.isFailure && record.settlementOutcome == nil
        }
        if records.count != originalCount { changed() }
    }

    private func resumePendingTasks() {
        reconcilePendingSettlements()
        for record in records where record.phase.isActive && record.settlementOutcome == nil {
            guard record.ownerUserID == nil || record.ownerUserID == AuthManager.shared.session?.user.id else { continue }
            guard let remoteID = record.remoteTaskID else { update(record.id, phase: .interrupted, progress: 0); continue }
            WidgetTaskClient.shared.resume(taskID: remoteID, cancellation: makeCancellation(for: record.id),
                progress: { [weak self] phase, value in self?.update(record.id, phase: phase, progress: value) },
                queue: { [weak self] info in self?.setQueue(record.id, info) },
                billing: { [weak self] value in self?.receiveBilling(record.id, value) },
                completion: { [weak self] result in self?.handleRemoteResult(record.id, result) })
        }
    }

    private func handleRemoteResult(_ id: UUID, _ result: Result<URL, Error>) {
        DispatchQueue.main.async { [weak self] in self?.handleResultOnMain(id, result) }
    }

    private func handleResultOnMain(_ id: UUID, _ result: Result<URL, Error>) {
        cancellations[id] = nil
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
        let allowedTypes = records.first(where: { $0.id == id })?.outputTypes
        URLSession.shared.downloadTask(with: url) { [weak self] temporary, response, error in
            guard let self else { return }
            guard let temporary, error == nil else { self.update(id, phase: .failed, progress: 0, error: error?.localizedDescription); return }
            do {
                try WidgetTaskClient.validateDownload(temporary, response: response, allowedTypes: allowedTypes)
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
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = self.records.firstIndex(where: { $0.id == id }),
                  self.records[index].phase != .cancelled,
                  self.records[index].settlementOutcome != "failed" else { return }
            self.records[index].outputPath = output.path
            self.records[index].outputURLString = remoteURL?.absoluteString
            self.records[index].settlementOutcome = "delivered"
            self.changed()
            // Persist the saved result before confirming a charge. After a
            // restart we must still know where the delivered file lives.
            self.save { [weak self] saved in
                guard let self, self.records.first(where: { $0.id == id })?.settlementOutcome == "delivered" else { return }
                if saved { self.reconcileSettlement(id) }
                else { self.update(id, phase: .failed, progress: 0, error: "Could not save the task. Check available disk space and try again.".localized) }
            }
        }
    }

    private func completeDelivery(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }),
              let output = records[index].output else { return }
        let remoteURL = records[index].outputURLString.flatMap(URL.init(string:))
        BillingResultAccess.mark(output)
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
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
    private func update(_ id: UUID, phase: WidgetTaskPhase, progress: Int, error: String? = nil) {
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            if self.records[index].phase == .cancelled && phase != .cancelled { return }
            self.records[index].phase = phase
            self.records[index].progress = progress
            self.records[index].errorMessage = error
            self.records[index].updatedAt = Date()
            if phase.isFailure || phase == .cancelled {
                if self.records[index].requestKey != nil || self.records[index].remoteTaskID != nil {
                    self.records[index].settlementOutcome = "failed"
                }
            }
            self.changed()
            self.reconcileSettlement(id)
        }
    }

    private func receiveBilling(_ id: UUID, _ value: WidgetTaskBilling) {
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            self.applyBilling(value, at: index)
            self.changed()
        }
    }

    private func applyBilling(_ value: WidgetTaskBilling, at index: Int) {
        let billingChanged = records[index].creditCost != value.creditCost
            || records[index].refundedCredits != value.refundedCredits
        if !value.taskID.isEmpty { records[index].remoteTaskID = value.taskID }
        records[index].creditCost = value.creditCost ?? records[index].creditCost
        records[index].refundedCredits = max(value.refundedCredits ?? 0, records[index].refundedCredits ?? 0)
        // Refresh the authoritative wallet rather than overwriting it with a
        // possibly older response from another concurrently running task.
        if billingChanged && records[index].ownerUserID == AuthManager.shared.session?.user.id {
            AuthManager.shared.refreshAccount()
        }
    }

    private func reconcilePendingSettlements() {
        for record in records where record.settlementOutcome != nil { reconcileSettlement(record.id) }
    }

    private func reconcileSettlement(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), let outcome = record.settlementOutcome,
              let user = AuthManager.shared.session?.user,
              record.ownerUserID == nil || record.ownerUserID == user.id,
              !settlementsInFlight.contains(id) else { return }
        if outcome == "delivered", record.output.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            update(id, phase: .failed, progress: 0, error: "The result could not be downloaded. Please check your connection and try again.".localized)
            return
        }
        settlementsInFlight.insert(id)
        WidgetTaskClient.shared.settle(taskID: record.remoteTaskID, requestKey: record.requestKey, outcome: outcome) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                // An acknowledgement may have committed before its response was
                // lost. Status lookup resolves that ambiguity without recharging.
                if case .failure(let error) = result,
                   let requestError = error as? WidgetTaskRequestError, requestError.statusCode == 409,
                   let remoteID = record.remoteTaskID {
                    WidgetTaskClient.shared.fetchBilling(taskID: remoteID) { [weak self] status in
                        DispatchQueue.main.async { self?.finishSettlement(id, outcome: outcome, result: status) }
                    }
                } else { self.finishSettlement(id, outcome: outcome, result: result) }
            }
        }
    }

    private func finishSettlement(_ id: UUID, outcome: String, result: Result<WidgetTaskBilling, Error>) {
        settlementsInFlight.remove(id)
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].settlementOutcome == outcome else { return }
        if case .success(let value) = result {
            let unsuccessful = ["failed", "expired", "cancelled"].contains(value.status)
            let refunded = (value.creditCost ?? 0) == 0 || (value.refundedCredits ?? 0) >= (value.creditCost ?? 0)
            let delivered = value.delivered == true && ["completed", "succeeded"].contains(value.status)
            if delivered || (unsuccessful && refunded) {
                applyBilling(value, at: index)
                records[index].settlementOutcome = nil
                settlementRetries[id] = nil
                if outcome == "delivered" && delivered { completeDelivery(id) }
                else if unsuccessful && outcome == "delivered" {
                    records[index].phase = .failed
                    records[index].errorMessage = "Result confirmation timed out. Credits were refunded. Please run the task again.".localized
                }
                changed()
                return
            }
        }
        // Keep the record and pending status on disk, including across sign-out.
        let attempt = (settlementRetries[id] ?? 0) + 1
        settlementRetries[id] = attempt
        let delay = min(60.0, 5 * pow(2, Double(min(attempt - 1, 4))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reconcileSettlement(id) }
    }

    private func changed() {
        let pending = records.filter { $0.settlementOutcome != nil || $0.phase.isActive }
        let history = records.filter { $0.settlementOutcome == nil && !$0.phase.isActive }
        records = (pending + history.prefix(max(0, 200 - pending.count))).sorted { $0.createdAt > $1.createdAt }
        save()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private var storeURL: URL { let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Glance", isDirectory: true); try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder.appendingPathComponent("widget-tasks.json") }
    private func load() { guard let data = try? Data(contentsOf: storeURL) else { return }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; records = (try? decoder.decode([WidgetTaskRecord].self, from: data)) ?? [] }
    private func save(completion: ((Bool) -> Void)? = nil) {
        let snapshot = records, url = storeURL
        ioQueue.async {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let saved: Bool
            do { try encoder.encode(snapshot).write(to: url, options: .atomic); saved = true }
            catch { saved = false }
            if let completion { DispatchQueue.main.async { completion(saved) } }
        }
    }

}

private extension URL { var taskKey: String { isFileURL ? standardizedFileURL.path : absoluteString } }
