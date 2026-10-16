import CryptoKit
import Darwin
import Foundation
import Security

/// Local billing state uses the same noninteractive preferences storage as
/// the account session. Keychain data is recovered once only when accessible.
enum BillingSecureStore {
  private static let lock = NSLock()
  private static let prefix = "glance.billing.store."
  static func read(_ key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    let storageKey = prefix + key
    if let data = UserDefaults.standard.data(forKey: storageKey) { return data }
    let marker = storageKey + ".keychainRollbackComplete"
    guard !UserDefaults.standard.bool(forKey: marker) else { return nil }
    UserDefaults.standard.set(true, forKey: marker)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "ai.mcreator.glance.billing", kSecAttrAccount as String: key,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    UserDefaults.standard.set(data, forKey: storageKey)
    return data
  }
  static func write(_ key: String, _ data: Data?) {
    lock.lock()
    defer { lock.unlock() }
    let storageKey = prefix + key
    UserDefaults.standard.set(true, forKey: storageKey + ".keychainRollbackComplete")
    if let data { UserDefaults.standard.set(data, forKey: storageKey) }
    else { UserDefaults.standard.removeObject(forKey: storageKey) }
  }
}

enum BillingIdentity {
  static let deviceID: String = {
    if let data = BillingSecureStore.read("device"), let value = String(data: data, encoding: .utf8)
    {
      return value
    }
    let value = UUID().uuidString
    BillingSecureStore.write("device", Data(value.utf8))
    return value
  }()
  static var deviceHash: String {
    SHA256.hash(data: Data(deviceID.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

struct BillingPrice: Codable {
  let amount: Int?
  let points: Int?
}
struct BillingProduct: Codable {
  let CNY: BillingPrice
  let USD: BillingPrice
  let launchCNY: BillingPrice?
  let launchUSD: BillingPrice?
  let launchUntil: String?
  let productID: String
  func price(_ currency: String, now: Date = Date()) -> BillingPrice {
    if let cutoff = BillingDates.parse(launchUntil), cutoff > now,
      let launch = currency == "CNY" ? launchCNY : launchUSD, launch.amount != nil
    {
      return launch
    }
    return currency == "CNY" ? CNY : USD
  }
}
struct BillingPack: Codable {
  let id: String
  let name: String
  let enabled: Bool
  let recommended: Bool
  let CNY: BillingPrice
  let USD: BillingPrice
  let productID: String
  func price(_ currency: String) -> BillingPrice { currency == "CNY" ? CNY : USD }
}
struct BillingPricing: Codable {
  let enabled: Bool
  let trialDays: Int
  let signupCredits: Int
  let proBonusCredits: Int
  let deviceLimit: Int
  let offlineDays: Int
  let releaseLimit: Int
  let confirmationThreshold: Int
  let queueMinutes: Int
  let maxAttempts: Int
  let updatesMonths: Int
  let renewalMonths: Int
  let pro: BillingProduct
  let renewal: BillingProduct
  let packs: [BillingPack]
  let supportEmail: String
  let termsURL: String
  let privacyURL: String
  let refundURL: String
  let lastCompatibleVersionURL: String
  let defaultCurrency: String
  let paymentsAvailable: Bool
  let serverTime: String
}
struct BillingTransaction: Decodable {
  let id: String
  let amount: Int
  let reason: String
  let note: String?
  let created_at: String
  let order_id: String?
  let task_id: String?
  let widget_name: String?
  let product: String?
  let currency: String?
  let order_amount: Int?
  var label: String {
    switch reason {
    case "signup", "signup_bonus": return "New account gift".localized
    case "purchase_credits": return "Credit top-up".localized
    case "pro_bonus": return "Pro purchase gift".localized
    case "widget_task": return widget_name ?? "Widget task".localized
    case "task_refund":
      return String(format: "%@ refunded".localized, widget_name ?? "Widget".localized)
    case "order_refund": return "Order refund recovery".localized
    case "admin_adjust": return note ?? "Balance adjustment".localized
    default: return note ?? reason
    }
  }
}
struct BillingWallet: Decodable {
  let balance: Int
  let transactions: [BillingTransaction]
}
struct BillingDevice: Decodable {
  let id: String
  let name: String
  let last_seen_at: String
  let current: Bool
}
struct BillingCredential: Codable {
  let payload: String
  let signature: String
  let keyID: String
}
struct BillingClaims: Decodable {
  let userID: Int
  let deviceHash: String
  let issuedAt: String
  let expiresAt: String
  let updatesUntil: String
  let sourceOrder: String
  let pro: Bool
}
struct BillingEntitlements: Decodable {
  let pro: Bool
  let proBonusEligible: Bool?
  let licenseStatus: String
  let updatesUntil: String?
  let purchasedAt: String?
  let currentDeviceID: String?
  let devices: [BillingDevice]
  let deviceLimit: Int
  let releasesRemaining: Int
  let trialStartedAt: String?
  let trialEndsAt: String?
  let trialVoided: Bool
  let trialActive: Bool
  let paidWidgetNoticeSeen: Bool
  let credential: BillingCredential?
  let serverTime: String
  let enforcementEnabled: Bool
}
struct BillingOrder: Codable {
  let id: String
  let product: String
  let packID: String?
  let currency: String
  let amount: Int
  let credits: Int
  let bonusCredits: Int
  let status: String
  let createdAt: String
  let paidAt: String?
  let refundedAt: String?
  let expiresAt: String
  let refundStatus: String?
  let refundReason: String?
  let intentID: String?
  var isPaid: Bool { status == "paid" || status == "refund_failed" }
  var isTerminal: Bool { ["paid", "refund_failed", "refunded", "expired"].contains(status) }
}
struct BillingCheckout: Decodable {
  let order: BillingOrder
  let orderID: String
  let checkoutUrl: String?
  let expiresAt: String?
}
struct BillingOrderStatus: Decodable {
  let order: BillingOrder
  let balance: Int
}
struct BillingOrderList: Decodable { let orders: [BillingOrder] }
struct BillingAPIError: LocalizedError {
  let code: String
  let message: String
  let details: [String: Any]?
  var errorDescription: String? { message.localized }
}
enum BillingDates {
  static func parse(_ value: String?) -> Date? {
    guard let value else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  static func string(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
  }
  static func display(_ value: String?) -> String {
    guard let date = parse(value) else { return "—" }
    let f = DateFormatter()
    f.dateStyle = .medium
    return f.string(from: date)
  }
}
struct BillingTrial: Codable {
  var startedAt: Date
  var lastSeen: Date
  var voided: Bool
  static func load() -> BillingTrial {
    if let data = BillingSecureStore.read("trial"),
      let value = try? JSONDecoder().decode(Self.self, from: data)
    {
      return value
    }
    let value = BillingTrial(startedAt: Date(), lastSeen: Date(), voided: false)
    value.save()
    return value
  }
  func save() { BillingSecureStore.write("trial", try? JSONEncoder().encode(self)) }
  mutating func observe(_ now: Date) {
    lastSeen = max(lastSeen, now)
    save()
  }
  func remainingDays(_ days: Int) -> Int {
    if voided { return 0 }
    return max(
      0,
      Int(
        ceil(
          (startedAt.addingTimeInterval(Double(days) * 86400).timeIntervalSince(
            max(lastSeen, Date()))) / 86400)))
  }
}

/// Saved Widget outputs keep their paid-result exemption even when the task
/// history is cleared or the file is moved on the same volume.
enum BillingResultAccess {
  private static let attribute = "ai.mcreator.glance.widget-result"
  static func mark(_ url: URL) {
    guard url.isFileURL else { return }
    var value: UInt8 = 1
    _ = withUnsafePointer(to: &value) { setxattr(url.path, attribute, $0, 1, 0, 0) }
  }
  static func contains(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    var cursor = url.standardizedFileURL
    for _ in 0..<8 {
      var value: UInt8 = 0
      let count = withUnsafeMutablePointer(to: &value) {
        getxattr(cursor.path, attribute, $0, 1, 0, 0)
      }
      if count == 1 && value == 1 { return true }
      let parent = cursor.deletingLastPathComponent()
      if parent.path == cursor.path { break }
      cursor = parent
    }
    return false
  }
}
