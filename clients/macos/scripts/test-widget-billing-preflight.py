"""Exercise the real preflight controller with inert UI/network doubles; never launch Glance."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1] / 'Glance/Sources'

def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

method = block((root / 'BillingCoordinator.swift').read_text(), '  func confirmWidgetTask(')
quote = block((root / 'WidgetTaskClient.swift').read_text(), 'struct WidgetTaskQuote: Codable {')
stubs = r'''
import Foundation
extension String { var localized: String { self } }
struct User { var id = 1 }
struct Session { var user = User() }
final class AuthManager { static let shared = AuthManager(); var session: Session? = Session() }
class NSWindow { var isVisible = true }
struct WidgetCommand { var id = "run" }
struct WidgetManifest { var id = "video"; var displayName = "Video Watermark"; var usesDurationBilling = true }
struct WidgetVideoEvidence: Codable {
    var durationSeconds: Double = 60
    var byteSize = 1024
    var sha256 = "hash"
    var dictionary: [String: Any] { ["durationSeconds": durationSeconds] }
    static var inspections = 0
    static func inspect(_ url: URL, completion: @escaping (Result<Self, Error>) -> Void) { inspections += 1; completion(.success(Self())) }
}
enum BillingDates {
    static func parse(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }
}
final class BillingManager {
    static let shared = BillingManager()
    var pending: [(Result<WidgetTaskQuote, Error>) -> Void] = []
    var events: [(String,String,String?)] = []
    func track(_ kind: String, id: String, journeyID: String?, feature: String) { events.append((kind,id,journeyID)) }
    func request(_ path: String, body: [String: Any], completion: @escaping (Result<WidgetTaskQuote, Error>) -> Void) {
        precondition(path == "/api/v2/task-quotes", "preflight must only call quote endpoint")
        pending.append(completion)
    }
    func refreshPricing(_ callback: (Result<Int, Error>) -> Void) { callback(.success(1)) }
    func reply(_ quote: WidgetTaskQuote) { pending.removeFirst()(.success(quote)) }
}
final class BillingWindow {
    var onDismiss: (() -> Void)?
    var onResumeTask: (() -> Void)?
    var taskJourneyID: String?
    var taskTopupOrderID: String?
    var taskName: String?
    var taskCost: Int?
    var taskBalance: Int?
    var requiresTaskConfirmation = false
    var autoSubmit = false
    var primary: (() -> Void)?
    var secondary: (() -> Void)?
    var state = ""
    var title = ""
    func present(over: NSWindow?) {}
    func dismiss() { state = "dismissed"; onDismiss?() }
    func showStatus(title: String, subtitle: String, rows: [(String,String)] = [], primary: String,
                    secondary: String? = nil, onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil) {
        self.title = title; state = "status"; self.primary = onPrimary; self.secondary = onSecondary
    }
    func showError(_ message: String, retry: (() -> Void)? = nil) { state = "error"; primary = retry }
    func showTopup() { state = "topup" }
}
final class WidgetTaskClient {
    static let shared = WidgetTaskClient()
    func prepareLocalInput(_ url: URL, completion: (Result<URL, Error>) -> Void) { completion(.success(url)) }
}
final class BillingCoordinator {
    var lastPanel: BillingWindow!
    func makePanel(over: NSWindow?) -> BillingWindow { lastPanel = BillingWindow(); return lastPanel }
    func retain(_ panel: BillingWindow) {}
'''
tests = r'''
func q(_ balance: Int, expired: Bool = false) -> WidgetTaskQuote {
    WidgetTaskQuote(quoteID: UUID().uuidString, mode: "duration", unitSeconds: 10, unitPrice: 100,
                    units: 6, totalCredits: 600,
                    expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(expired ? -1 : 600)),
                    balance: balance, shortfall: max(0,600-balance), evidence: WidgetVideoEvidence())
}
func check(_ name: String, _ condition: Bool) { precondition(condition,name); print("PASS: " + name) }
let billing = BillingManager.shared
let coordinator = BillingCoordinator()
let source = [URL(fileURLWithPath: "/tmp/input.mp4")]
var accepted: [WidgetTaskQuote] = []
var cancelled = 0
func begin(_ widget: WidgetManifest = WidgetManifest()) {
    coordinator.confirmWidgetTask(widget: widget, command: WidgetCommand(), mediaURLs: source, over: nil) {
        if let quote = $0 { accepted.append(quote) } else { cancelled += 1 }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
begin()
check("checking does not create or accept a task", accepted.isEmpty && billing.pending.count == 1)
billing.reply(q(500))
check("insufficient credits opens top-up first", coordinator.lastPanel.state == "topup" && accepted.isEmpty && coordinator.lastPanel.taskBalance == 500)
check("insufficient event carries the task journey", billing.events.last?.0 == "insufficient" && billing.events.last?.2 == coordinator.lastPanel.taskJourneyID)
let topupJourney = coordinator.lastPanel.taskJourneyID
coordinator.lastPanel.taskTopupOrderID = "order_topup_test"
check("automatic submission is disabled", coordinator.lastPanel.requiresTaskConfirmation && !coordinator.lastPanel.autoSubmit)
coordinator.lastPanel.onResumeTask?()
billing.reply(q(1500))
check("payment completion only shows confirmation", accepted.isEmpty && coordinator.lastPanel.title == "Confirm Video Watermark")
let confirm = coordinator.lastPanel.primary!
confirm()
confirm()
check("explicit confirmation accepts exactly once", accepted.count == 1 && accepted[0].totalCredits == 600)
check("confirmed task retains the recharge journey and order", accepted[0].billingIntentID == topupJourney && accepted[0].topupOrderID == "order_topup_test")
let restored = try JSONDecoder().decode(WidgetTaskQuote.self, from: JSONEncoder().encode(accepted[0]))
check("task correlation survives persistence", restored.billingIntentID == topupJourney && restored.topupOrderID == "order_topup_test")
begin()
coordinator.lastPanel.dismiss()
billing.reply(q(1500))
check("late quote after cancel cannot start work", accepted.count == 1 && cancelled == 1)
begin()
billing.reply(q(1500, expired: true))
coordinator.lastPanel.primary?()
check("expired quote is refreshed before acceptance", accepted.count == 1 && billing.pending.count == 1)
billing.reply(q(100))
check("recheck can return to recharge", coordinator.lastPanel.state == "topup" && accepted.count == 1)
coordinator.lastPanel.dismiss()
begin()
billing.reply(q(1500))
AuthManager.shared.session = nil
coordinator.lastPanel.primary?()
check("account change cannot submit another account's quote", accepted.count == 1)

// Fixed-price Widgets use the same gate, without video-specific preparation.
AuthManager.shared.session = Session()
let fixed = WidgetManifest(id: "image-tool", displayName: "Image Tool", usesDurationBilling: false)
func fixedQuote(_ balance: Int, cost: Int = 30) -> WidgetTaskQuote {
    WidgetTaskQuote(quoteID: UUID().uuidString, mode: "fixed", unitSeconds: 0, unitPrice: cost,
                    units: 1, totalCredits: cost,
                    expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)),
                    balance: balance, shortfall: max(0,cost-balance), evidence: nil)
}
let inspections = WidgetVideoEvidence.inspections
begin(fixed)
billing.reply(fixedQuote(20))
check("fixed-price Widget opens recharge before accepting work", coordinator.lastPanel.state == "topup" && coordinator.lastPanel.taskCost == 30 && accepted.count == 1)
check("ordinary Widgets do not use video duration inspection", WidgetVideoEvidence.inspections == inspections)
coordinator.lastPanel.onResumeTask?()
billing.reply(fixedQuote(50))
check("ordinary Widget still requires confirmation after recharge", coordinator.lastPanel.title == "Confirm Image Tool" && accepted.count == 1)
coordinator.lastPanel.primary?()
check("ordinary Widget confirms the exact quoted cost", accepted.count == 2 && accepted.last?.totalCredits == 30 && accepted.last?.mode == "fixed")
begin(fixed)
billing.reply(fixedQuote(30))
check("exactly enough credits goes directly to confirmation", coordinator.lastPanel.title == "Confirm Image Tool" && accepted.count == 2)
coordinator.lastPanel.secondary?()
check("cancelling ordinary Widget confirmation starts no work", accepted.count == 2)
begin(fixed)
billing.reply(fixedQuote(0))
coordinator.lastPanel.dismiss()
check("closing ordinary Widget recharge starts no work", accepted.count == 2)
begin(fixed)
billing.reply(fixedQuote(0, cost: 0))
check("free Widget needs no recharge", coordinator.lastPanel.title == "Confirm Image Tool" && coordinator.lastPanel.taskCost == 0)
coordinator.lastPanel.dismiss()

'''
with tempfile.TemporaryDirectory(prefix='glance-billing-preflight-') as directory:
    script = Path(directory) / 'check.swift'
    script.write_text(stubs + method + '\n}\n' + quote + tests)
    subprocess.run(['swift', '-module-cache-path', directory + '/modules', str(script)], check=True)
