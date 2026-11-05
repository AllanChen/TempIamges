import AppKit

/// Standard account commands, separate from the Figma-matched purchase panels.
/// All requests are authenticated; the server owns seat limits and revocation.
final class AccountActions: NSObject {
    static let shared = AccountActions()
    private var busy = false

    @objc func manageTeam(_ sender: Any?) {
        request("/team") { [weak self] result in
            guard let self else { return }
            let role = result["role"] as? String ?? "none"
            let members = result["members"] as? [[String: Any]] ?? []
            let invites = result["invites"] as? [[String: Any]] ?? []
            var actions: [(String, () -> Void)] = []
            if role == "owner" {
                actions.append(("Invite a member".localized, { self.invite() }))
                for member in members {
                    guard let id = member["id"] as? Int, let email = member["email"] as? String else { continue }
                    actions.append(("Remove member".localized + " · " + email, {
                        self.confirm("Remove member".localized, email) { self.request("/team/members/\(id)", method: "DELETE") { _ in self.refresh(); self.manageTeam(nil) } }
                    }))
                }
                for invite in invites {
                    guard let id = invite["id"] as? String, let email = invite["email"] as? String else { continue }
                    actions.append(("Revoke invitation".localized + " · " + email, { self.request("/team/invites/" + id, method: "DELETE") { _ in self.manageTeam(nil) } }))
                }
            } else if role == "member" {
                actions.append(("Leave team".localized, {
                    self.confirm("Leave team".localized, "Your team Pro access will end. Your credits remain yours.".localized) {
                        self.request("/team/leave", method: "POST", body: [:]) { _ in self.refresh(); self.manageTeam(nil) }
                    }
                }))
            } else {
                actions.append(("Accept invitation".localized, {
                    guard let code = self.prompt("Accept invitation".localized, "Sign in with the invited email and paste the invitation code.".localized) else { return }
                    self.request("/team/accept", method: "POST", body: ["code": code]) { _ in self.refresh(); self.manageTeam(nil) }
                }))
            }
            let alert = NSAlert()
            alert.messageText = "Team account".localized
            let used = result["usedSeats"] as? Int ?? 0
            alert.informativeText = role == "none" ? "A five-person plan includes the purchaser and four invited accounts. Each account has one Mac and its own credits.".localized : String(format: "%d of 5 seats in use. Each account has one Mac and its own credits.".localized, used)
            let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
            choices.addItems(withTitles: actions.map { $0.0 })
            alert.accessoryView = choices
            alert.addButton(withTitle: "Continue".localized)
            alert.addButton(withTitle: "Close".localized)
            NSApp.activate(ignoringOtherApps: true)
            if present(alert) == .alertFirstButtonReturn, actions.indices.contains(choices.indexOfSelectedItem) { actions[choices.indexOfSelectedItem].1() }
        }
    }

    private func invite() {
        guard let email = prompt("Invite a member".localized, "Enter their Glance account email. The invitation expires in 7 days.".localized) else { return }
        request("/team/invites", method: "POST", body: ["email": email]) { [weak self] result in
            guard let self, let code = result["invitationCode"] as? String else { return }
            let alert = NSAlert()
            alert.messageText = "Invitation ready".localized
            alert.informativeText = "Share this code privately. The recipient opens Glance → Team account and accepts it while signed in with the invited email.".localized
            let field = NSTextField(string: code)
            field.isEditable = false; field.isSelectable = true
            field.frame = NSRect(x: 0, y: 0, width: 440, height: 44)
            alert.accessoryView = field
            alert.addButton(withTitle: "Copy code".localized); alert.addButton(withTitle: "Close".localized)
            if present(alert) == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
            }
            self.manageTeam(nil)
        }
    }

    @objc func deleteAccount(_ sender: Any?) {
        guard let session = AuthManager.shared.session else { message("Please sign in first.".localized); return }
        let warning = "This permanently deletes your account and Pro access, revokes all sessions and queues uploaded media for removal. Unspent credits are forfeited; no automatic cash refund is issued. Resolve refunds and active tasks first. Required financial records are retained. If you own a team, all members lose team access. Type your account email to continue.".localized
        guard let email = prompt("Delete account".localized, warning) else { return }
        guard email.lowercased() == session.user.email.lowercased() else {
            message("The email does not match your signed-in account.".localized); return
        }
        confirm("Permanently delete account?".localized, session.user.email) { [weak self] in
            self?.request("", method: "DELETE", body: ["email": session.user.email, "confirm": "DELETE"]) { _ in
                AuthManager.shared.signOut()
                self?.message("Account deleted. Uploaded media cleanup is queued and retried automatically.".localized)
            }
        }
    }

    private func refresh() { BillingManager.shared.refreshEntitlements(activate: true); AuthManager.shared.refreshAccount() }
    private func prompt(_ title: String, _ detail: String) -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue".localized); alert.addButton(withTitle: "Cancel".localized)
        NSApp.activate(ignoringOtherApps: true)
        guard present(alert) == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { message("Enter a value to continue.".localized); return nil }
        return value
    }
    private func confirm(_ title: String, _ detail: String, action: () -> Void) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "Cancel".localized); alert.addButton(withTitle: "Confirm".localized)
        if present(alert) == .alertSecondButtonReturn { action() }
    }
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.layout()
        alert.window.setFrame(ScreenManager.shared.centeredFrame(for: alert.window.frame.size, near: NSEvent.mouseLocation), display: false)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
    private func message(_ text: String) { let alert = NSAlert(); alert.messageText = text; _ = present(alert) }
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, completion: @escaping ([String: Any]) -> Void) {
        guard !busy else { return }
        guard let session = AuthManager.shared.session else { message("Please sign in first.".localized); return }
        busy = true
        var request = URLRequest(url: URL(string: "https://api.glancepreview.com/api/v2/account" + path)!)
        request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer " + session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                // Never apply an old account's response after switching accounts.
                guard AuthManager.shared.session?.token == session.token else { return }
                guard let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (response as? HTTPURLResponse)?.statusCode == 200, json["success"] as? Bool == true,
                      let result = json["result"] as? [String: Any] else {
                    let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                    let message = (json?["error"] as? [String: Any])?["message"] as? String
                    self.message((message ?? error?.localizedDescription ?? "Could not complete this request. Please try again.").localized); return
                }
                completion(result)
            }
        }.resume()
    }
}
