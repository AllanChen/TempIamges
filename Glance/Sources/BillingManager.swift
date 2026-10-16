import AppKit
import CryptoKit

/// Account, pricing and authorization state. Callers and completions use main.
/// Hosted checkout return URLs are hints only; order status comes from the API.
final class BillingManager {
  static let shared = BillingManager()
  static let didChange = Notification.Name("Glance.BillingDidChange")
  private let api = URL(string: "https://api.glance.mcreator.ai")!
  private(set) var pricing: BillingPricing?
  private(set) var entitlements: BillingEntitlements?
  private(set) var wallet: BillingWallet?
  private(set) var trial = BillingTrial.load()
  private var authenticatedUserID: Int?
  private var authenticatedToken: String?
  private let launchSessionToken = AuthManager.shared.session?.token
  private var credential: BillingCredential?
  private(set) var deviceWasReleased = false
  private var observer: NSObjectProtocol?
  private var enforcementEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "glance.billing.enforcement") }
    set { UserDefaults.standard.set(newValue, forKey: "glance.billing.enforcement") }
  }
  private init() {
    pricing = UserDefaults.standard.data(forKey: "glance.billing.pricing").flatMap {
      try? JSONDecoder().decode(BillingPricing.self, from: $0)
    }
    credential = BillingSecureStore.read("credential").flatMap {
      try? JSONDecoder().decode(BillingCredential.self, from: $0)
    }
    observer = NotificationCenter.default.addObserver(
      forName: .authDidChange, object: nil, queue: .main
    ) { [weak self] _ in self?.accountChanged(allowActivation: true) }
  }
  var remainingTrialDays: Int { trial.remainingDays(pricing?.trialDays ?? 14) }
  var trialBadge: String? {
    guard !hasPro, !trial.voided, remainingTrialDays <= 3, remainingTrialDays > 0 else {
      return nil
    }
    return String(format: "Trial: %d days left".localized, remainingTrialDays)
  }
  private var signedClaims: BillingClaims? {
    guard let credential, credential.keyID == "glance-market-2026-02",
      let keyData = Data(base64Encoded: "F4eg6N56Z8z3CC7E4CUV0YecA6NpeHpAtx0/NFsUGFs="),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
      let signature = Data(base64Encoded: credential.signature),
      key.isValidSignature(signature, for: Data(credential.payload.utf8)),
      let payload = Data(base64Encoded: credential.payload),
      let claims = try? JSONDecoder().decode(BillingClaims.self, from: payload), claims.pro,
      claims.userID == AuthManager.shared.storedUserID,
      claims.deviceHash == BillingIdentity.deviceHash
    else { return nil }
    return claims
  }
  var verifiedClaims: BillingClaims? {
    guard let claims = signedClaims, let expiry = BillingDates.parse(claims.expiresAt),
      expiry > max(Date(), trial.lastSeen)
    else { return nil }
    return claims
  }
  var offlineAuthorizationExpired: Bool { signedClaims != nil && verifiedClaims == nil }
  var hasPro: Bool { verifiedClaims != nil }
  var needsUpdates: Bool {
    guard let claims = verifiedClaims,
      let release = Bundle.main.object(forInfoDictionaryKey: "GlanceFeatureReleaseDate") as? String,
      let releasedAt = BillingDates.parse(release),
      let until = BillingDates.parse(claims.updatesUntil),
      Bundle.main.object(forInfoDictionaryKey: "GlanceSecurityUpdate") as? Bool != true
    else { return false }
    return releasedAt > until
  }
  var localToolsAllowed: Bool {
    // Roll out gating only with a working purchase path, per PRD P2.
    if !enforcementEnabled { return true }
    return (hasPro && !needsUpdates) || (!trial.voided && remainingTrialDays > 0)
  }
  func start() {
    trial.observe(Date())
    track("trial_started", id: "trial-started", feature: nil)
    NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let window = note.object as? NSWindow, !(window is BillingWindow) else { return }
      self?.presentLaunchNotice(over: window)
    }
    refreshPricing { _ in self.accountChanged() }
  }
  func track(
    _ kind: String, id: String = UUID().uuidString, journeyID: String? = nil, feature: String? = nil
  ) {
    var body: [String: Any] = [
      "id": id.count < 16 ? "glance-event-" + id : id, "kind": kind,
      "startedAt": BillingDates.string(trial.startedAt),
    ]
    if let journeyID { body["journeyID"] = journeyID }
    if let feature { body["feature"] = feature }
    request("/api/v2/billing/events", body: body, authenticated: AuthManager.shared.isSignedIn) {
      (_: Result<EmptyBillingResponse, Error>) in
    }
  }
  func trackTrialActivity(_ feature: String) {
    guard !hasPro, !trial.voided, remainingTrialDays > 0 else { return }
    track("trial_activity", feature: feature)
  }
  func observeForUse() { trial.observe(Date()) }
  private var launchNoticeShown = false
  func presentLaunchNotice(over parent: NSWindow) {
    guard !launchNoticeShown else { return }
    launchNoticeShown = true
    let storeKey = "trial-notice"
    if BillingSecureStore.read(storeKey) == nil {
      BillingSecureStore.write(storeKey, Data([1]))
      if !hasPro && !trial.voided {
        BillingCoordinator.shared.showNotice(
          String(format: "Your %d-day full trial has started.".localized, pricing?.trialDays ?? 14),
          over: parent)
      }
    } else if remainingTrialDays == 1 && !hasPro {
      BillingCoordinator.shared.showNotice("Your full trial ends tomorrow.".localized, over: parent)
    } else if remainingTrialDays == 0 && !hasPro && localToolsAllowed == false
      && BillingSecureStore.read("trial-ended-notice") == nil
    {
      BillingSecureStore.write("trial-ended-notice", Data([1]))
      BillingCoordinator.shared.showTrialEnded(over: parent)
    }
  }
  func refreshPricing(_ completion: @escaping (Result<BillingPricing, Error>) -> Void) {
    request("/api/v2/pricing", authenticated: false) { (result: Result<BillingPricing, Error>) in
      if case .success(let value) = result {
        self.pricing = value
        if let cached = try? JSONEncoder().encode(value) {
          UserDefaults.standard.set(cached, forKey: "glance.billing.pricing")
        }
        self.enforcementEnabled = value.enabled && value.paymentsAvailable
        if let now = BillingDates.parse(value.serverTime) { self.trial.observe(now) }
        self.changed()
      } else if case .failure(let error as BillingAPIError) = result,
        error.code == "not_found" {
        // A cached offer must not enable checkout against an older service
        // deployment that has no pricing or order routes.
        self.pricing = nil
        UserDefaults.standard.removeObject(forKey: "glance.billing.pricing")
        self.enforcementEnabled = false
        self.changed()
      }
      completion(result)
    }
  }
  func refreshWallet(_ completion: ((Result<BillingWallet, Error>) -> Void)? = nil) {
    request("/api/v2/account/credits") { (result: Result<BillingWallet, Error>) in
      if case .success(let value) = result {
        self.wallet = value
        AuthManager.shared.updateCredits(value.balance)
        self.changed()
        if let user = AuthManager.shared.session?.user.id,
          let gift = value.transactions.first(where: {
            $0.reason == "signup_bonus" && $0.amount > 0
          }),
          let created = BillingDates.parse(gift.created_at),
          Date().timeIntervalSince(created) < 120,
          BillingSecureStore.read("gift-notice-\(user)") == nil, let window = NSApp.keyWindow
        {
          BillingSecureStore.write("gift-notice-\(user)", Data([1]))
          BillingCoordinator.shared.showNotice(
            String(format: "%d credits have arrived.".localized, gift.amount), over: window)
        }
      }
      completion?(result)
    }
  }
  func refreshEntitlements(
    activate: Bool = false, completion: ((Result<BillingEntitlements, Error>) -> Void)? = nil
  ) {
    request("/api/v2/account/entitlements") { (result: Result<BillingEntitlements, Error>) in
      switch result {
      case .failure: completion?(result)
      case .success(let value):
        self.apply(value)
        if activate && value.licenseStatus == "active" && !value.pro
          && value.devices.count < value.deviceLimit
        {
          self.activateDevice(completion: completion)
        } else {
          completion?(result)
        }
      }
    }
  }
  func activateDevice(completion: ((Result<BillingEntitlements, Error>) -> Void)? = nil) {
    request(
      "/api/v2/account/devices/activate",
      body: ["deviceID": BillingIdentity.deviceID, "name": Host.current().localizedName ?? "Mac"]
    ) { (result: Result<BillingEntitlements, Error>) in
      if case .success(let value) = result { self.apply(value) }
      completion?(result)
    }
  }
  func releaseDevice(
    _ id: String, completion: @escaping (Result<BillingEntitlements, Error>) -> Void
  ) {
    request("/api/v2/account/devices/\(id)/release", body: [:]) {
      (result: Result<BillingEntitlements, Error>) in
      if case .success(let value) = result { self.apply(value) }
      completion(result)
    }
  }
  private func apply(_ value: BillingEntitlements) {
    if credential != nil && value.licenseStatus == "active" && !value.pro {
      deviceWasReleased = true
    }
    if value.pro { deviceWasReleased = false }
    entitlements = value
    enforcementEnabled = value.enforcementEnabled
    credential = value.credential
    BillingSecureStore.write(
      "credential", value.credential.flatMap { try? JSONEncoder().encode($0) })
    if value.trialVoided { trial.voided = true }
    if let start = BillingDates.parse(value.trialStartedAt) {
      trial.startedAt = min(trial.startedAt, start)
    }
    trial.observe(BillingDates.parse(value.serverTime) ?? Date())
    changed()
  }
  private func accountChanged(allowActivation: Bool = false) {
    let id = AuthManager.shared.storedUserID
    let token = AuthManager.shared.session?.token
    guard id != authenticatedUserID || token != authenticatedToken else { return }
    let shouldActivate =
      allowActivation && token != launchSessionToken && token != authenticatedToken
    authenticatedUserID = id
    authenticatedToken = token
    entitlements = nil
    wallet = nil
    deviceWasReleased = false
    if id == nil {
      credential = nil
      BillingSecureStore.write("credential", nil)
      changed()
      return
    }
    guard token != nil else {
      changed()
      return
    }
    request("/api/v2/account/trial", body: ["startedAt": BillingDates.string(trial.startedAt)]) {
      (result: Result<BillingEntitlements, Error>) in
      if case .success(let value) = result { self.apply(value) }
      self.refreshEntitlements(activate: shouldActivate)
      self.refreshWallet()
      BillingCoordinator.shared.restorePendingPayments()
    }
  }
  func createOrder(
    product: String, pack: BillingPack?, currency: String, key: String,
    displayedPrice: BillingPrice, intentID: String? = nil,
    completion: @escaping (Result<BillingCheckout, Error>) -> Void
  ) {
    guard pricing != nil else {
      completion(.failure(AuthError.message("Pricing is unavailable. Please try again.".localized)))
      return
    }
    let price = displayedPrice
    guard let amount = price.amount else {
      completion(.failure(AuthError.message("This product is not available yet.".localized)))
      return
    }
    var expected: [String: Any] = ["amount": amount]
    if let points = price.points { expected["points"] = points }
    var body: [String: Any] = [
      "product": product, "currency": currency, "expectedPrice": expected,
      "language": Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en",
    ]
    if let pack { body["packID"] = pack.id }
    if let intentID { body["intentID"] = intentID }
    request("/api/v2/orders", body: body, idempotencyKey: key, completion: completion)
  }
  func order(_ id: String, completion: @escaping (Result<BillingOrderStatus, Error>) -> Void) {
    request("/api/v2/orders/\(id)", completion: completion)
  }
  func orders(completion: @escaping (Result<BillingOrderList, Error>) -> Void) {
    request("/api/v2/orders", completion: completion)
  }
  func refund(
    _ id: String, reason: String,
    completion: @escaping (Result<EmptyBillingResponse, Error>) -> Void
  ) {
    request("/api/v2/orders/\(id)/refund", body: ["reason": reason], completion: completion)
  }
  func acknowledgePaidWidget() {
    guard let id = AuthManager.shared.session?.user.id else { return }
    UserDefaults.standard.set(true, forKey: "glance.billing.widgetNotice.\(id)")
    request("/api/v2/account/widget-notice", body: [:]) {
      (_: Result<EmptyBillingResponse, Error>) in
    }
  }
  var needsPaidWidgetNotice: Bool {
    guard let id = AuthManager.shared.session?.user.id else { return true }
    return entitlements?.paidWidgetNoticeSeen != true
      && !UserDefaults.standard.bool(forKey: "glance.billing.widgetNotice.\(id)")
  }
  private func changed() { NotificationCenter.default.post(name: Self.didChange, object: nil) }
  func money(_ cents: Int?, currency: String) -> String {
    guard let cents else { return "Not available yet".localized }
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    f.locale = currency == "CNY" ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
    return f.string(from: NSNumber(value: Double(cents) / 100))
      ?? "\(currency) \(Double(cents)/100)"
  }
  func request<T: Decodable>(
    _ path: String, body: [String: Any]? = nil, authenticated: Bool = true,
    idempotencyKey: String? = nil,
    completion: @escaping (Result<T, Error>) -> Void
  ) {
    let token = AuthManager.shared.session?.token
    if authenticated && token == nil {
      completion(.failure(AuthError.message("Please sign in to continue.".localized)))
      return
    }
    var request = URLRequest(url: api.appendingPathComponent(path))
    request.timeoutInterval = 30
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(BillingIdentity.deviceID, forHTTPHeaderField: "X-Glance-Device")
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    if let key = idempotencyKey { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
    URLSession.shared.dataTask(with: request) { data, response, error in
      DispatchQueue.main.async {
        if authenticated && token != AuthManager.shared.session?.token {
          completion(
            .failure(AuthError.message("The account changed. Please try again.".localized)))
          return
        }
        do {
          if let error { throw error }
          guard let data, let http = response as? HTTPURLResponse else {
            throw WidgetError.unavailable
          }
          if !(200..<300).contains(http.statusCode) {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let issue = object?["error"] as? [String: Any]
            if http.statusCode == 401 { AuthManager.shared.invalidateOnlineSession() }
            throw BillingAPIError(
              code: issue?["code"] as? String ?? "request_failed",
              message: issue?["message"] as? String ?? "Request failed. Please try again.",
              details: issue?["details"] as? [String: Any])
          }
          let envelope = try JSONDecoder().decode(ApiEnvelope<T>.self, from: data)
          guard envelope.success, let value = envelope.result else { throw WidgetError.unavailable }
          completion(.success(value))
        } catch { completion(.failure(error)) }
      }
    }.resume()
  }
}
struct EmptyBillingResponse: Decodable {}
