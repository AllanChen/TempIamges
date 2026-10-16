import AppKit

/// Account purchases and payments stay separate from Widget execution.
final class BillingCoordinator {
  static let shared = BillingCoordinator()
  private final class Payment {
    let order: BillingOrder
    let ownerID: Int
    let panel: BillingWindow
    weak var parent: NSWindow?
    let started = Date()
    var poll: DispatchWorkItem?
    var finished = false
    var abandoned = false
    var displayedSlow = false
    init(
      order: BillingOrder, ownerID: Int, panel: BillingWindow, parent: NSWindow?
    ) {
      self.order = order
      self.ownerID = ownerID
      self.panel = panel
      self.parent = parent
    }
  }
  private var panels: [UUID: BillingWindow] = [:]
  private var payments: [String: Payment] = [:]
  private var owners: [NSObjectProtocol] = []
  private let toast = InspectToastWindow()
  private init() {
    owners.append(
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification, object: nil, queue: .main
      ) { [weak self] note in
        guard let self, let closed = note.object as? NSWindow else { return }
        for payment in self.payments.values where payment.parent === closed {
          payment.abandoned = true
          payment.panel.dismiss()
        }
      })
    owners.append(
      NotificationCenter.default.addObserver(forName: .authDidChange, object: nil, queue: .main) {
        [weak self] _ in
        guard let self else { return }
        let id = AuthManager.shared.session?.user.id
        for payment in self.payments.values where payment.ownerID != id {
          payment.poll?.cancel()
          payment.abandoned = true
        }
      })
  }
  private func makePanel(over parent: NSWindow?) -> BillingWindow {
    let panel = BillingWindow()
    panel.currency = BillingManager.shared.pricing?.defaultCurrency ?? "USD"
    panel.onCheckout = { [weak self, weak panel, weak parent] product, pack, currency, price in
      guard let panel else { return }
      self?.checkout(
        product: product, pack: pack, currency: currency, displayedPrice: price, panel: panel,
        parent: parent)
    }
    panel.onResumeOrder = { [weak self, weak panel, weak parent] order in
      guard let panel else { return }
      self?.resumePayment(order, panel: panel, parent: parent)
    }
    return panel
  }
  private static func featureKey(_ title: String) -> String {
    if title == "Compress".localized || title == "Compress…".localized { return "compress" }
    if title == "Copy Image".localized { return "copy" }
    if title.localizedCaseInsensitiveContains("base64") { return "base64" }
    if title == "Export".localized { return "convert" }
    if title == "Save".localized { return "edit" }
    return "export"
  }
  @discardableResult
  func requireLocalTool(_ title: String, over parent: NSWindow?, source: URL? = nil) -> Bool {
    let manager = BillingManager.shared
    manager.observeForUse()
    // Paid Widget results and captures are usable independently of Pro.
    if let source,
      WidgetTaskManager.shared.completedRecord(for: source) != nil
        || BillingResultAccess.contains(source) || CaptureOutput.isCapture(source)
    {
      return true
    }
    guard !manager.localToolsAllowed else {
      let key = Self.featureKey(title)
      manager.trackTrialActivity(key)
      return true
    }
    manager.track("locked_click", feature: Self.featureKey(title))
    let panel = makePanel(over: parent)
    if manager.entitlements?.licenseStatus == "active" && !manager.hasPro {
      if manager.deviceWasReleased {
        panel.showStatus(
          title: "This Mac was released".localized,
          subtitle: "Your files, history and credits are kept.".localized,
          primary: "Reactivate this Mac".localized, secondary: "Continue free".localized,
          onPrimary: {
            manager.activateDevice { result in
              if case .success = result { panel.showAccount() } else { panel.showDevices() }
            }
          }, onSecondary: { panel.dismiss() }, iconName: "BillingWarning")
      } else {
        panel.showDevices()
      }
      retain(panel)
      panel.present(over: parent)
      return false
    }
    if manager.offlineAuthorizationExpired {
      panel.showStatus(
        title: "Connect to verify your Pro license".localized,
        subtitle:
          "Your offline authorization has expired. Connect to refresh it without purchasing again."
          .localized,
        primary: "Verify license".localized, secondary: "Continue free".localized,
        onPrimary: {
          let verify = {
            manager.refreshEntitlements { result in
              if case .failure(let error) = result {
                panel.showError(error.localizedDescription)
              } else {
                panel.showAccount()
              }
            }
          }
          if AuthManager.shared.isSignedIn { verify() } else { panel.showLogin(completion: verify) }
        }, onSecondary: { panel.dismiss() })
      retain(panel)
      panel.present(over: parent)
      return false
    }
    if manager.needsUpdates {
      panel.showStatus(
        title: "This version needs renewed feature updates".localized,
        subtitle: "Your previous compatible version keeps Pro permanently.".localized,
        rows: [
          (
            "Feature updates until".localized,
            BillingDates.display(manager.verifiedClaims?.updatesUntil)
          )
        ],
        primary: "Renew feature updates".localized,
        secondary: "Download compatible version".localized,
        onPrimary: { panel.showPro(renewal: true) },
        onSecondary: {
          if let raw = manager.pricing?.lastCompatibleVersionURL, let url = URL(string: raw),
            url.scheme == "https"
          {
            NSWorkspace.shared.open(url)
          }
        })
      retain(panel)
      panel.present(over: parent)
      return false
    }
    panel.showStatus(
      title: String(format: "%@ requires Pro".localized, title),
      subtitle:
        "Viewing, comparing, capturing and AI Widgets remain available. Files and results are kept."
        .localized,
      primary: "View Pro".localized, secondary: "Cancel".localized,
      onPrimary: { [weak panel] in panel?.showPro(renewal: manager.needsUpdates) },
      onSecondary: { [weak panel] in panel?.dismiss() })
    retain(panel)
    panel.present(over: parent)
    return false
  }
  private func retain(_ panel: BillingWindow) {
    let key = UUID()
    panels[key] = panel
    panel.onDismiss = { [weak self] in self?.panels.removeValue(forKey: key) }
  }
  func showAuthenticationError(_ message: String) {
    if panels.values.contains(where: { $0.displayAuthenticationError(message) }) { return }
    let panel = makePanel(over: NSApp.mainWindow)
    retain(panel)
    panel.showLogin { [weak panel] in panel?.showAccount() }
    panel.present(over: NSApp.mainWindow)
    panel.displayAuthenticationError(message)
  }
  func showAccount(over parent: NSWindow? = nil, wallet: Bool = false) {
    let panel = makePanel(over: parent)
    retain(panel)
    let show = { [weak panel] in if wallet { panel?.showWallet() } else { panel?.showAccount() } }
    if AuthManager.shared.isSignedIn {
      show()
      BillingManager.shared.refreshWallet { _ in panel.refreshAccountState() }
      BillingManager.shared.refreshEntitlements { _ in panel.refreshAccountState() }
    } else {
      panel.showLogin { BillingManager.shared.refreshWallet { _ in show() } }
    }
    panel.present(over: parent)
  }
  func showPro(over parent: NSWindow? = nil) {
    let panel = makePanel(over: parent)
    retain(panel)
    BillingManager.shared.refreshPricing { result in
      switch result {
      case .success: panel.showPro(renewal: BillingManager.shared.needsUpdates)
      case .failure(let error): panel.showError(error.localizedDescription)
      }
      panel.present(over: parent)
    }
  }
  private func checkout(
    product: String, pack: BillingPack?, currency: String, displayedPrice: BillingPrice,
    panel: BillingWindow, parent: NSWindow?
  ) {
    guard AuthManager.shared.isSignedIn else {
      panel.showLogin(purchase: product != "credits") {
        // The user reviews the refreshed offer after login; never open
        // checkout automatically from a stale anonymous price.
        BillingManager.shared.refreshPricing { _ in
          if product == "credits" {
            panel.showTopup()
          } else {
            panel.showPro(renewal: product == "renewal")
          }
        }
      }
      return
    }
    let key = UUID().uuidString
    func create() {
      BillingManager.shared.createOrder(
        product: product, pack: pack, currency: currency, key: key, displayedPrice: displayedPrice
      ) { [weak self, weak panel, weak parent] result in
        guard let self, let panel else { return }
        switch result {
        case .failure(let error as BillingAPIError) where error.code == "price_changed":
          BillingManager.shared.refreshPricing { _ in
            panel.showStatus(
              title: "The price changed".localized,
              subtitle: "Review the latest price before paying.".localized,
              primary: "Review price".localized,
              onPrimary: {
                if product == "credits" {
                  panel.showTopup()
                } else {
                  panel.showPro(renewal: product == "renewal")
                }
              })
          }
        case .failure(let error as BillingAPIError) where error.code == "pending_order":
          if let data = error.details,
            let bytes = try? JSONSerialization.data(withJSONObject: data),
            let order = try? JSONDecoder().decode(BillingOrder.self, from: bytes)
          {
            panel.showStatus(
              title: "You have an unpaid order".localized, subtitle: order.id,
              primary: "Continue payment".localized,
              secondary: "Not now".localized,
              onPrimary: { self.resumePayment(order, panel: panel, parent: parent) },
              onSecondary: { panel.dismiss() })
          } else {
            panel.showError(error.localizedDescription)
          }
        case .failure(let error): panel.showError(error.localizedDescription, retry: create)
        case .success(let checkout):
          guard let userID = AuthManager.shared.session?.user.id else { return }
          let payment = Payment(
            order: checkout.order, ownerID: userID, panel: panel, parent: parent
          )
          self.track(payment)
          if let raw = checkout.checkoutUrl, let url = URL(string: raw), url.scheme == "https" {
            NSWorkspace.shared.open(url)
          }
          self.showPayment(payment)
          self.poll(payment)
        }
      }
    }
    create()
  }
  private func showPayment(_ payment: Payment, confirming: Bool = false) {
    guard !payment.abandoned else { return }
    let slow = Date().timeIntervalSince(payment.started) > 120
    payment.panel.showStatus(
      title: slow
        ? "Payment confirmation is taking longer".localized
        : confirming
          ? "Confirming your payment".localized : "Complete payment in your browser".localized,
      subtitle: slow
        ? "If you have been charged, your purchase will arrive automatically. Please do not pay again."
          .localized
        : "Your purchase is confirmed only after the payment provider notifies Glance.".localized,
      rows: [
        ("Order".localized, payment.order.id),
        (
          "Amount".localized,
          BillingManager.shared.money(payment.order.amount, currency: payment.order.currency)
        ),
      ],
      primary: slow ? "Contact support".localized : "I have completed payment".localized,
      secondary: slow ? "Check again".localized : "Abandon payment".localized,
      onPrimary: { [weak self, weak payment] in
        guard let self, let payment else { return }
        if slow {
          self.contactSupport(order: payment.order.id)
        } else {
          self.showPayment(payment, confirming: true)
          self.poll(payment)
        }
      },
      onSecondary: { [weak self, weak payment] in
        guard let self, let payment else { return }
        if slow { self.poll(payment) } else { self.confirmAbandon(payment) }
      }, iconName: "BillingTasks")
    if payment.order.currency == "CNY" {
      payment.panel.showPaymentHelp("WeChat Pay is unavailable?".localized) {
        [weak self, weak payment] in if let payment { self?.showWeChatHelp(payment) }
      }
    }
  }
  private func showWeChatHelp(_ payment: Payment) {
    payment.panel.showStatus(
      title: "WeChat Pay is unavailable?".localized,
      subtitle:
        "The cashier may hide WeChat Pay when the buyer's monthly merchant limit is reached."
        .localized,
      primary: "Switch to USD payment".localized, secondary: "Cancel".localized,
      onPrimary: { [weak self, weak payment] in
        guard let self, let payment else { return }
        BillingManager.shared.request("/api/v2/orders/\(payment.order.id)/abandon", body: [:]) {
          (result: Result<EmptyBillingResponse, Error>) in
          switch result {
          case .failure(let error):
            payment.panel.showError(
              error.localizedDescription, retry: { self.showWeChatHelp(payment) })
          case .success:
            payment.abandoned = true
            payment.panel.currency = "USD"
            if payment.order.product == "credits" {
              payment.panel.showTopup()
            } else {
              payment.panel.showPro(renewal: payment.order.product == "renewal")
            }
          }
        }
      }, onSecondary: { [weak self] in self?.showPayment(payment) }, iconName: "BillingWarning",
      explanation:
        "If you have paid, check the order first. Otherwise you can use a USD order with card, Apple Pay or Google Pay."
        .localized)
  }
  private func confirmAbandon(_ payment: Payment) {
    payment.panel.showStatus(
      title: "Abandon this payment?".localized,
      subtitle:
        "If you have already paid, check the result instead of paying again. Unpaid checkout sessions expire automatically."
        .localized,
      primary: "I have paid, check again".localized, secondary: "Abandon payment".localized,
      onPrimary: { [weak self] in
        self?.showPayment(payment, confirming: true)
        self?.poll(payment)
      },
      onSecondary: {
        payment.abandoned = true
        BillingManager.shared.request("/api/v2/orders/\(payment.order.id)/abandon", body: [:]) {
          (_: Result<EmptyBillingResponse, Error>) in
        }
        payment.panel.dismiss()
      })
  }
  private func poll(_ payment: Payment) {
    payment.poll?.cancel()
    guard !payment.finished, payment.ownerID == AuthManager.shared.session?.user.id else { return }
    BillingManager.shared.order(payment.order.id) { [weak self, weak payment] result in
      guard let self, let payment, !payment.finished else { return }
      if case .success(let status) = result {
        if status.order.isPaid {
          self.fulfilled(payment, status: status)
          return
        }
        if status.order.status == "refunded" {
          payment.finished = true
          self.payments.removeValue(forKey: payment.order.id)
          BillingManager.shared.refreshEntitlements()
          BillingManager.shared.refreshWallet()
          return
        }
        if status.order.status == "expired" {
          payment.finished = true
          if !payment.abandoned {
            payment.panel.showStatus(
              title: "Order expired".localized,
              subtitle: "If payment was completed, it will still be credited after confirmation."
                .localized,
              primary: "Try again".localized,
              onPrimary: {
                if payment.order.product == "credits" {
                  payment.panel.showTopup()
                } else {
                  payment.panel.showPro(renewal: payment.order.product == "renewal")
                }
              })
          }
          return
        }
      }
      if !payment.abandoned, !payment.displayedSlow, Date().timeIntervalSince(payment.started) > 120
      {
        payment.displayedSlow = true
        self.showPayment(payment, confirming: true)
      }
      let next = DispatchWorkItem { [weak self, weak payment] in
        if let payment { self?.poll(payment) }
      }
      payment.poll = next
      DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: next)
    }
  }
  private func fulfilled(_ payment: Payment, status: BillingOrderStatus) {
    payment.finished = true
    payment.poll?.cancel()
    forget(payment.order.id, userID: payment.ownerID)
    AuthManager.shared.updateCredits(status.balance)
    BillingManager.shared.refreshWallet()
    BillingManager.shared.refreshEntitlements(activate: true) { [weak self, weak payment] _ in
      guard let self, let payment else { return }
      if !payment.abandoned {
        if payment.order.product != "credits"
          && BillingManager.shared.entitlements?.licenseStatus == "active"
          && !BillingManager.shared.hasPro
        {
          payment.panel.showDevices()
        } else {
          if payment.order.product == "renewal" {
            payment.panel.showStatus(
              title: "Feature updates extended".localized,
              subtitle: "Feature updates until".localized + " "
                + BillingDates.display(BillingManager.shared.entitlements?.updatesUntil),
              primary: "Done".localized, onPrimary: { payment.panel.dismiss() },
              iconName: "BillingSuccess",
              explanation:
                "Your buyout license and credits are unchanged. This version can now use Pro."
                .localized)
            return
          }
          var rows = [("Current balance".localized, String(status.balance))]
          if payment.order.product != "credits" {
            rows = [
              (
                "Purchase gift".localized,
                String(format: "%d credits".localized, status.order.bonusCredits)
              ),
              ("Current balance".localized, String(status.balance)),
              (
                "Feature updates until".localized,
                BillingDates.display(BillingManager.shared.entitlements?.updatesUntil)
              ),
              (
                "Active Macs".localized,
                "\(BillingManager.shared.entitlements?.devices.count ?? 0) / \(BillingManager.shared.entitlements?.deviceLimit ?? 2)"
              ),
            ]
          }
          payment.panel.showStatus(
            title: payment.order.product == "credits"
              ? "Credits have arrived".localized : "Pro is activated".localized,
            subtitle: payment.order.id, rows: rows, primary: "Done".localized,
            onPrimary: {
              if payment.parent?.isVisible == true {
                payment.panel.dismiss()
              } else if payment.order.product == "credits" {
                payment.panel.showWallet()
              } else {
                payment.panel.showAccount()
              }
            }, iconName: "BillingSuccess")
        }

      } else if let parent = payment.parent ?? NSApp.keyWindow {
        self.toast.show(
          message: "Your purchase has arrived.".localized, kind: .success, over: parent)
      }
    }
  }
  func handlePaymentReturn(_ url: URL) -> Bool {
    guard url.scheme == "glance", url.host == "payment", url.path == "/return",
      let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "order"
      })?.value,
      id.range(of: "^order_[A-Za-z0-9-]{1,80}$", options: .regularExpression) != nil
    else { return false }
    if let payment = payments[id], payment.ownerID == AuthManager.shared.session?.user.id {
      payment.finished = false
      payment.abandoned = false
      payment.panel.present(over: payment.parent?.isVisible == true ? payment.parent : nil)
      showPayment(payment, confirming: true)
      poll(payment)
    } else {
      let panel = makePanel(over: nil)
      retain(panel)
      if AuthManager.shared.isSignedIn {
        lookupReturn(id, panel: panel)
      } else {
        panel.showLogin { [weak self, weak panel] in
          if let panel { self?.lookupReturn(id, panel: panel) }
        }
        panel.present()
      }
    }
    return true
  }
  private func lookupReturn(_ id: String, panel: BillingWindow) {
    BillingManager.shared.order(id) { [weak self, weak panel] result in
      guard let self, let panel, let owner = AuthManager.shared.session?.user.id else { return }
      switch result {
      case .failure(let error): panel.showError(error.localizedDescription)
      case .success(let status):
        let payment = Payment(
          order: status.order, ownerID: owner, panel: panel, parent: nil)
        self.track(payment)
        self.showPayment(payment, confirming: true)
        self.poll(payment)
      }
      panel.present()
    }
  }
  private func resumePayment(_ order: BillingOrder, panel: BillingWindow, parent: NSWindow?) {
    BillingManager.shared.request("/api/v2/orders/\(order.id)/checkout", body: [:]) {
      [weak self] (result: Result<BillingCheckout, Error>) in
      switch result {
      case .failure(let error): panel.showError(error.localizedDescription)
      case .success(let checkout):
        guard let self, let owner = AuthManager.shared.session?.user.id else { return }
        let payment = Payment(
          order: checkout.order, ownerID: owner, panel: panel, parent: parent)
        self.track(payment)
        if let raw = checkout.checkoutUrl, let url = URL(string: raw), url.scheme == "https" {
          NSWorkspace.shared.open(url)
        }
        self.showPayment(payment)
        self.poll(payment)
      }
    }
  }
  private func track(_ payment: Payment) {
    payments[payment.order.id] = payment
    remember(payment.order.id, userID: payment.ownerID)
    let onDismiss = payment.panel.onDismiss
    payment.panel.onDismiss = { [weak payment] in
      payment?.abandoned = true
      onDismiss?()
    }
  }
  private func remember(_ id: String, userID: Int) {
    let key = "glance.billing.pending.\(userID)"
    var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
    if !ids.contains(id) { ids.append(id) }
    UserDefaults.standard.set(ids, forKey: key)
  }
  private func forget(_ id: String, userID: Int) {
    let key = "glance.billing.pending.\(userID)"
    UserDefaults.standard.set(
      (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != id }, forKey: key)
  }

  func showNotice(_ message: String, over parent: NSWindow) {
    toast.show(message: message, kind: .info, over: parent, duration: 4)
  }
  func showTrialEnded(over parent: NSWindow) {
    let panel = makePanel(over: parent)
    retain(panel)
    panel.showStatus(
      title: "Your full trial has ended".localized,
      subtitle:
        "Viewing, comparing, capturing and AI Widgets remain available. Files and results are kept."
        .localized,
      primary: "View Pro".localized, secondary: "Continue free".localized,
      onPrimary: { panel.showPro() }, onSecondary: { panel.dismiss() })
    panel.present(over: parent)
  }
  func restorePendingPayments() {
    guard let owner = AuthManager.shared.session?.user.id else { return }
    for id in UserDefaults.standard.stringArray(forKey: "glance.billing.pending.\(owner)") ?? []
    where payments[id]?.finished != false {
      BillingManager.shared.order(id) { [weak self] result in
        guard let self, AuthManager.shared.session?.user.id == owner,
          case .success(let status) = result
        else { return }
        let panel = self.makePanel(over: nil)
        let payment = Payment(
          order: status.order, ownerID: owner, panel: panel, parent: nil)
        payment.abandoned = true
        self.payments[id] = payment
        if status.order.isPaid {
          self.fulfilled(payment, status: status)
        } else if status.order.status == "pending" {
          self.poll(payment)
        } else {
          self.forget(id, userID: owner)
          self.payments.removeValue(forKey: id)
        }
      }
    }
  }
  private func contactSupport(order: String) {
    guard let email = BillingManager.shared.pricing?.supportEmail, !email.isEmpty else { return }
    var c = URLComponents()
    c.scheme = "mailto"
    c.path = email
    c.queryItems = [URLQueryItem(name: "subject", value: "Glance payment \(order)")]
    if let url = c.url { NSWorkspace.shared.open(url) }
  }
}
