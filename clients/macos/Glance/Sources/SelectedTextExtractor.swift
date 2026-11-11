import AppKit
import ApplicationServices
import CoreGraphics

struct SelectionResult {
    let text: String
    let bounds: CGRect?  // AX screen coords (top-left origin, y-down). nil when unavailable.
    /// Folders the selection most likely refers to, closest first: the source
    /// window's folder (Terminal.app and Ghostty publish a tab's working
    /// directory as its proxy document; editors publish the open file), then
    /// the working directories of the user's shells. Bare file names resolve here.
    var contextDirectories: [URL] = []
}

/// Working directories of the user's interactive shells, read from the process
/// table (the user's own processes need no permission). This covers terminals
/// that publish no window folder (VS Code, Cursor, iTerm2, Warp): shells started
/// by the source app come first, then the most recently started.
enum ShellDirectories {
    private static let shellNames: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "nu", "pwsh", "xonsh", "elvish"
    ]

    static func candidates(sourcePID: pid_t?, limit: Int = 8) -> [URL] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let filled = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        guard filled > 0 else { return [] }

        struct Process { let ppid: pid_t; let name: String; let started: UInt64; let hasTerminal: Bool }
        let uid = getuid()
        var processes: [pid_t: Process] = [:]
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == uid else { continue }
            let name = withUnsafeBytes(of: info.pbi_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            processes[pid] = Process(ppid: pid_t(info.pbi_ppid), name: name, started: info.pbi_start_tvsec,
                                     hasTerminal: info.e_tdev != 0 && info.e_tdev != UInt32.max)
        }
        func isDescendant(_ pid: pid_t, of ancestor: pid_t) -> Bool {
            var current = pid
            for _ in 0..<64 {
                guard let process = processes[current], process.ppid > 1 else { return false }
                if process.ppid == ancestor { return true }
                current = process.ppid
            }
            return false
        }
        // Interactive shells only: a controlling terminal rules out scripts' shells.
        let shells = processes.filter { shellNames.contains($0.value.name) && $0.value.hasTerminal }
            .map { entry in (pid: entry.key, process: entry.value,
                             own: sourcePID.map { isDescendant(entry.key, of: $0) } ?? false) }
            .sorted { $0.own != $1.own ? $0.own : $0.process.started > $1.process.started }

        var seen = Set<String>()
        var directories: [URL] = []
        for shell in shells {
            guard let path = workingDirectory(of: shell.pid), seen.insert(path).inserted else { continue }
            directories.append(URL(fileURLWithPath: path, isDirectory: true))
            if directories.count >= limit { break }
        }
        return directories
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) {
            String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty || path == "/" ? nil : path
    }
}

class SelectedTextExtractor {
    /// A bounded AX-only read used to decide whether a visible Peek should
    /// close or be replaced. Clipboard fallback is intentionally excluded:
    /// synthesizing Copy would make the toggle slow and disturb the source app.
    func extractSelectionFast(timeout: TimeInterval = 0.05,
                              completion: @escaping (SelectionResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.readViaAXWithTimeout(timeout: timeout)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func extractSelection(completion: @escaping (SelectionResult?) -> Void) {
        extractSelection(fromPID: nil, completion: completion)
    }

    /// `fromPID` scopes the AX read to a specific source application. This is
    /// required on repeat activations: after our own windows take focus, the
    /// system-wide focused element no longer holds the user's selection, but
    /// the source app's focused element still does.
    func extractSelection(fromPID pid: pid_t?, completion: @escaping (SelectionResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let axResult = self.readViaAXWithTimeout(timeout: 1.0, fromPID: pid) {
                DispatchQueue.main.async { completion(axResult) }
                return
            }

            Logger.info("SelectedTextExtractor: AX yielded nothing or timed out, trying clipboard")

            if let clipboardResult = self.readViaClipboard() {
                DispatchQueue.main.async { completion(clipboardResult) }
                return
            }

            DispatchQueue.main.async { completion(nil) }
        }
    }

    func readClipboardDirectly(completion: @escaping (SelectionResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let result = self.readClipboardDirectly()
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - AX path (native Cocoa apps)

    private func readViaAXWithTimeout(timeout: TimeInterval, fromPID: pid_t? = nil) -> SelectionResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SelectionResult?
        DispatchQueue.global(qos: .userInitiated).async {
            result = self.readViaAX(fromPID: fromPID)
            semaphore.signal()
        }
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            Logger.info("SelectedTextExtractor: AX read timed out after \(timeout)s")
            return nil
        }
        return result
    }

    private func readViaAX(fromPID: pid_t? = nil) -> SelectionResult? {
        let systemWide: AXUIElement
        if let fromPID {
            systemWide = AXUIElementCreateApplication(fromPID)
        } else {
            systemWide = AXUIElementCreateSystemWide()
        }

        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusResult == .success,
              let raw = focusedElement,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            Logger.info("SelectedTextExtractor: No focused element (status=\(focusResult.rawValue))")
            return nil
        }
        let element = raw as! AXUIElement

        var selected: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        guard selResult == .success,
              let val = selected,
              CFGetTypeID(val) == CFStringGetTypeID() else {
            Logger.info("SelectedTextExtractor: kAXSelectedText unavailable (status=\(selResult.rawValue))")
            return nil
        }

        let text = (val as! CFString) as String
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: AX selected text empty")
            return nil
        }

        let bounds = readSelectionBounds(element: element)
        var sourcePID: pid_t = 0
        let window = readContextDirectory(element: element)
        let shells = ShellDirectories.candidates(
            sourcePID: AXUIElementGetPid(element, &sourcePID) == .success ? sourcePID : fromPID)
        var contexts = window.map { [$0] } ?? []
        contexts += shells.filter { $0 != window }
        Logger.info("SelectedTextExtractor: AX selected='\(Logger.redact(trimmed))' bounds=\(bounds.map { "\($0)" } ?? "nil") context=\(window == nil ? "none" : "window") + \(shells.count) shell dir(s)")
        return SelectionResult(text: trimmed, bounds: bounds, contextDirectories: contexts)
    }

    /// The selection's window `AXDocument` as a folder. Runs on the AX read queue.
    private func readContextDirectory(element: AXUIElement) -> URL? {
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) != .success {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success,
                  AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                                kAXFocusedWindowAttribute as CFString, &window) == .success
            else { return nil }
        }
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXDocumentAttribute as CFString,
                                            &document) == .success,
              let raw = document as? String, let url = URL(string: raw), url.isFileURL else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        return (isDirectory.boolValue ? url : url.deletingLastPathComponent()).standardizedFileURL
    }

    private func readSelectionBounds(element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeResult == .success,
              let rangeVal = rangeRef,
              CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &range), range.length > 0 else {
            return nil
        }

        var rangeForParam = range
        guard let rangeAxValue = AXValueCreate(.cfRange, &rangeForParam) else {
            return nil
        }
        var boundsRef: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAxValue,
            &boundsRef
        )
        guard boundsResult == .success,
              let boundsVal = boundsRef,
              CFGetTypeID(boundsVal) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else {
            return nil
        }
        return rect
    }

    func readClipboardDirectly() -> SelectionResult? {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else {
            Logger.info("SelectedTextExtractor: Clipboard contains no text")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: Clipboard text is empty")
            return nil
        }
        Logger.info("SelectedTextExtractor: Direct clipboard read='\(Logger.redact(trimmed))' (no bounds)")
        return SelectionResult(text: trimmed, bounds: nil)
    }

    // MARK: - Clipboard fallback (universal, works in VSCode/Cursor/Sublime/web)

    private func readViaClipboard() -> SelectionResult? {
        let pb = NSPasteboard.general
        let oldChangeCount = pb.changeCount
        let savedItems = snapshotPasteboard(pb)
        Logger.info("SelectedTextExtractor: clipboard pre-changeCount=\(oldChangeCount)")

        // The user is holding the hotkey. We synthesize a Cmd+C key event with
        // its own flags (.maskCommand only), which overrides the physical
        // modifier state for that one event — so the target app sees a clean
        // Cmd+C, not Cmd+Shift+C.
        guard sendCmdC() else {
            Logger.info("SelectedTextExtractor: Failed to synthesize Cmd+C")
            return nil
        }

        // Poll until the target app updates the pasteboard, with a hard cap.
        var copied: String?
        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            if pb.changeCount != oldChangeCount {
                copied = pb.string(forType: .string)
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        let postChangeCount = pb.changeCount
        if postChangeCount != oldChangeCount {
            // Only rewrite the pasteboard when our Cmd+C actually replaced it;
            // an unconditional rewrite bumps changeCount for clipboard managers
            // and drops lazily-provided types.
            restorePasteboard(pb, items: savedItems)
        } else {
            guardAgainstLateCopy(pb, expectedChangeCount: oldChangeCount, items: savedItems)
        }

        guard let text = copied else {
            Logger.info("SelectedTextExtractor: Clipboard unchanged after Cmd+C (pre=\(oldChangeCount), post=\(postChangeCount)). Likely no selection or app didn't honour Cmd+C.")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.info("SelectedTextExtractor: Clipboard text empty")
            return nil
        }
        Logger.info("SelectedTextExtractor: Clipboard selected='\(Logger.redact(trimmed))' (no bounds)")
        return SelectionResult(text: trimmed, bounds: nil)
    }

    private func sendCmdC() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 0x08  // kVK_ANSI_C
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        var snapshot: [NSPasteboardItem] = []
        for item in pb.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            snapshot.append(copy)
        }
        return snapshot
    }

    /// Some apps honour Cmd+C after our 250 ms poll window. Watch briefly and
    /// put the user's clipboard back if that late write lands.
    private func guardAgainstLateCopy(_ pb: NSPasteboard, expectedChangeCount: Int, items: [NSPasteboardItem]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline {
                if pb.changeCount != expectedChangeCount {
                    Logger.info("SelectedTextExtractor: late Cmd+C write detected, restoring clipboard")
                    self?.restorePasteboard(pb, items: items)
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private func restorePasteboard(_ pb: NSPasteboard, items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }
}
