import AppKit
import CoreText

/// PRD v0.4 Figma reference nodes: login 286:252, top-up 286:952,
/// wallet 286:1329, Pro 286:1694, account 286:2008, devices 286:2140.
/// Coordinates are top-origin design coordinates; the root is explicitly flipped.
final class BillingWindow: NSPanel, NSWindowDelegate, NSTextFieldDelegate {
  enum Page { case login, code, wallet, topup, pro, account, devices, orders, status }
  private final class Root: NSView { override var isFlipped: Bool { true } }
  private let root = Root(frame: NSRect(x: 0, y: 0, width: 640, height: 600))
  private var handlers: [String: () -> Void] = [:]
  private var observers: [NSObjectProtocol] = []
  private var emailField: NSTextField?
  private var codeField: NSTextField?
  private var codeFields: [NSTextField] = []
  private var reasonField: NSTextField?
  private var autoCheck: NSButton?
  private var resendAt = Date.distantPast
  private var resendTimer: Timer?
  private var resendButton: NSButton?
  private var email = ""
  private var loginJourneyID: String?
  private var loginPurchase = false
  private var loginFreeWidget = false
  private var inFlight = false
  private var page = Page.status
  private var onLogin: (() -> Void)?
  private var returnPage: Page = .account
  private var latestStatus: (() -> Void)?
  var onDismiss: (() -> Void)?
  var currency = "USD"
  private var selectedDeviceID: String?
  var selectedPackID: String?
  var autoSubmit = false
  var taskName: String?
  var taskCost: Int?
  var pendingTaskCount = 0
  var onCheckout: ((String, BillingPack?, String, BillingPrice) -> Void)?
  var onResumeTask: (() -> Void)?
  var onResumeOrder: ((BillingOrder) -> Void)?
  var onAutoSubmitChange: ((Bool) -> Void)?
  private let bg = NSColor(srgbRed: 11 / 255, green: 12 / 255, blue: 15 / 255, alpha: 1)
  private let surface = NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1)
  private let accent = NSColor(srgbRed: 232 / 255, green: 168 / 255, blue: 124 / 255, alpha: 1)
  private let ink = NSColor(srgbRed: 243 / 255, green: 238 / 255, blue: 232 / 255, alpha: 1)
  private let secondary = NSColor(srgbRed: 170 / 255, green: 164 / 255, blue: 160 / 255, alpha: 1)

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.borderless],
      backing: .buffered, defer: false)
    contentView = root
    delegate = self
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    appearance = NSAppearance(named: .darkAqua)
    root.wantsLayer = true
    root.layer?.backgroundColor = bg.cgColor
    root.layer?.cornerRadius = 14
    root.layer?.masksToBounds = true
    root.layer?.borderWidth = 1
    root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    observers.append(
      NotificationCenter.default.addObserver(forName: .authDidChange, object: nil, queue: .main) {
        [weak self] _ in
        guard let self else { return }
        if AuthManager.shared.isSignedIn, let completion = self.onLogin {
          if let journey = self.loginJourneyID {
            BillingManager.shared.track(
              "login_success", id: "login-success-" + journey, journeyID: journey)
          }
          self.loginJourneyID = nil
          self.onLogin = nil
          self.resendTimer?.invalidate()
          self.inFlight = false
          completion()
        }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: BillingManager.didChange, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self, self.isVisible, !self.inFlight else { return }
        switch self.page {
        case .wallet: self.showWallet()
        case .account: self.showAccount()
        case .topup: self.showTopup()
        default: break
        }
      })
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    resendTimer?.invalidate()
  }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  func present(over parent: NSWindow? = nil) {
    NSApp.activate(ignoringOtherApps: true)
    if let parent, parent !== self {
      if sheetParent !== parent {
        if let previous = sheetParent { previous.endSheet(self) }
        parent.beginSheet(self)
      }
    } else {
      setFrame(
        ScreenManager.shared.centeredFrame(
          for: NSSize(width: 640, height: 600), near: NSEvent.mouseLocation), display: true)
      makeKeyAndOrderFront(nil)
    }
  }
  func dismiss() {
    onLogin = nil
    resendTimer?.invalidate()
    if let parent = sheetParent { parent.endSheet(self) }
    orderOut(nil)
    onDismiss?()
  }
  func windowWillClose(_ notification: Notification) { onDismiss?() }
  override func cancelOperation(_ sender: Any?) { dismiss() }
  private func reset(
    _ title: String, subtitle: String = "", centered: Bool = true, status: Bool = false,
    iconName: String = "BillingStatusInfo"
  ) {
    root.subviews.forEach { $0.removeFromSuperview() }
    handlers.removeAll()
    emailField = nil
    codeField = nil
    codeFields.removeAll()
    reasonField = nil
    autoCheck = nil
    resendButton = nil
    let controls = [NSColor.systemRed, .systemYellow, .systemGreen]
    for (index, color) in controls.enumerated() {
      let dot = button(
        "", frame: NSRect(x: 20 + 26 * CGFloat(index), y: 18, width: 12, height: 12), primary: false
      ) { [weak self] in
        if index == 0 { self?.dismiss() }
      }
      (dot as? BillingActionButton)?.fillColor = .clear
      dot.wantsLayer = true
      dot.layer?.backgroundColor = color.cgColor
      dot.layer?.cornerRadius = 6
    }
    label(
      "Glance · " + "Account".localized, x: 166, y: 14, width: 308, size: 12, align: .center,
      color: secondary)
    box(
      x: 0, y: 47, width: 640, height: 1, color: NSColor.white.withAlphaComponent(0.07), radius: 0)
    label(
      title, x: 64, y: status ? 152 : 110, width: 512, size: 25, weight: .semibold,
      align: centered ? .center : .left, height: 34)
    label(
      subtitle, x: centered ? 84 : 64, y: status ? 192 : 150, width: centered ? 472 : 512,
      size: 12, align: centered ? .center : .left, color: secondary, height: 38)
    if status {
      box(
        x: 296, y: 86, width: 48, height: 48,
        color: iconName == "BillingWarning"
          ? NSColor(srgbRed: 48 / 255, green: 36 / 255, blue: 29 / 255, alpha: 1)
          : iconName == "BillingSuccess"
            ? NSColor(srgbRed: 26 / 255, green: 43 / 255, blue: 35 / 255, alpha: 1) : surface,
        radius: 24)
      let mark = NSImageView(frame: NSRect(x: 309, y: 99, width: 22, height: 22))
      mark.image = NSImage(named: iconName)
      mark.imageScaling = .scaleProportionallyUpOrDown
      root.addSubview(mark)
    }
  }
  @discardableResult
  private func label(
    _ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 12,
    weight: NSFont.Weight = .regular, align: NSTextAlignment = .left,
    color: NSColor? = nil, height: CGFloat = 24, parent: NSView? = nil
  ) -> NSTextField {
    let node = BillingLabel(wrappingLabelWithString: value)
    node.font = PanelStyle.inspectFont(ofSize: size, weight: weight)
    node.textColor = color ?? ink
    node.alignment = align
    node.isSelectable = false
    node.lineBreakMode = .byWordWrapping
    node.frame = NSRect(x: x, y: y, width: width, height: height)
    (parent ?? root).addSubview(node)
    return node
  }
  private func box(
    x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor, radius: CGFloat = 8
  ) {
    let view = NSView(frame: NSRect(x: x, y: y, width: width, height: height))
    view.wantsLayer = true
    view.layer?.backgroundColor = color.cgColor
    view.layer?.cornerRadius = radius
    root.addSubview(view)
  }
  @discardableResult
  private func button(
    _ title: String, frame: NSRect, primary: Bool = true, parent: NSView? = nil,
    action: @escaping () -> Void
  ) -> NSButton {
    let id = UUID().uuidString
    handlers[id] = action
    let view = BillingActionButton(frame: frame)
    view.title = title
    view.identifier = NSUserInterfaceItemIdentifier(id)
    view.target = self
    view.action = #selector(pressed(_:))
    view.isBordered = false
    view.primary = primary
    view.fillColor = primary ? accent : surface
    view.inkColor =
      primary ? NSColor(srgbRed: 33 / 255, green: 19 / 255, blue: 13 / 255, alpha: 1) : ink
    (parent ?? root).addSubview(view)
    return view
  }
  @objc private func pressed(_ sender: NSButton) {
    if let key = sender.identifier?.rawValue { handlers[key]?() }
  }
  private func primary(_ title: String, action: @escaping () -> Void) {
    button(title, frame: NSRect(x: 160, y: 500, width: 320, height: 40), action: action).isEnabled =
      !inFlight
  }
  private func quiet(_ title: String, y: CGFloat = 544, action: @escaping () -> Void) {
    let node = button(
      title, frame: NSRect(x: 168, y: y, width: 304, height: 28), primary: false, action: action)
    if let node = node as? BillingActionButton {
      node.fillColor = .clear
      node.inkColor = secondary
    }
  }
  private func row(
    _ name: String, _ value: String, y: CGFloat, color: NSColor? = nil, width: CGFloat = 512,
    x: CGFloat = 64
  ) {
    label(name, x: x, y: y + 5, width: width * 0.57, color: secondary)
    label(
      value, x: x + width * 0.60, y: y + 5, width: width * 0.40, weight: .medium, align: .right,
      color: color)
  }
  private func note(_ value: String) {
    label(value, x: 40, y: 578, width: 560, size: 11, align: .center, color: secondary, height: 20)
  }
  private func inlineError(_ message: String) {
    root.subviews.filter { $0.identifier?.rawValue == "billing-error" }.forEach {
      $0.removeFromSuperview()
    }
    let text = label(
      message, x: 100, y: 458, width: 440, align: .center, color: PanelStyle.failure, height: 38)
    text.identifier = NSUserInterfaceItemIdentifier("billing-error")
    inFlight = false
    root.subviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = true }
  }
  @discardableResult
  func displayAuthenticationError(_ message: String) -> Bool {
    guard isVisible, page == .login || page == .code else { return false }
    inlineError(message)
    return true
  }
  func showLogin(purchase: Bool = false, freeWidget: Bool = false, completion: @escaping () -> Void)
  {
    page = .login
    loginPurchase = purchase
    loginFreeWidget = freeWidget
    if onLogin == nil || loginJourneyID == nil {
      let journey = UUID().uuidString
      loginJourneyID = journey
      BillingManager.shared.track(
        "login_prompt", id: "login-prompt-" + journey, journeyID: journey,
        feature: purchase ? "pro" : "widget")
    }
    onLogin = completion
    reset(
      purchase ? "Sign in to buy Pro".localized : "Sign in to use AI Widgets".localized,
      subtitle: freeWidget
        ? "Sign in to keep your tasks and results together.".localized
        : String(
          format: "New accounts receive %d credits.".localized,
          BillingManager.shared.pricing?.signupCredits ?? 100))
    button(
      "Continue with Google".localized, frame: NSRect(x: 140, y: 216, width: 360, height: 40),
      primary: false
    ) {
      AuthManager.shared.openGoogleSignIn()
    }
    label(
      "Or use an email code".localized, x: 140, y: 270, width: 360, size: 11, align: .center,
      color: secondary)
    label("Email address".localized, x: 140, y: 298, width: 360, weight: .medium)
    let field = NSTextField(frame: NSRect(x: 140, y: 319, width: 360, height: 44))
    styleInput(field)
    field.placeholderString = "you@example.com"
    field.stringValue = email
    root.addSubview(field)
    emailField = field
    button("Send code".localized, frame: NSRect(x: 140, y: 373, width: 360, height: 40)) {
      [weak self] in self?.sendCode()
    }
    label(
      "Your image and Widget inputs are kept while you sign in.".localized, x: 140, y: 428,
      width: 360, align: .center, color: secondary, height: 40)
    let terms = button(
      "Terms of service".localized, frame: NSRect(x: 140, y: 566, width: 175, height: 28),
      primary: false
    ) { [weak self] in self?.openPolicy("terms") }
    let privacy = button(
      "Privacy policy".localized, frame: NSRect(x: 325, y: 566, width: 175, height: 28),
      primary: false
    ) { [weak self] in self?.openPolicy("privacy") }
    [terms, privacy].forEach { ($0 as? BillingActionButton)?.fillColor = .clear }
  }
  private func styleInput(_ field: NSTextField) {
    field.cell = BillingInputCell(textCell: field.stringValue)
    field.font = PanelStyle.inspectFont(ofSize: 13)
    field.textColor = ink
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.wantsLayer = true
    field.layer?.backgroundColor = surface.cgColor
    field.layer?.cornerRadius = 8
    field.layer?.borderWidth = 1
    field.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
  }
  private func sendCode() {
    guard !inFlight else { return }
    email = emailField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? email
    guard email.contains("@"), email.contains("."), !email.contains(" ") else {
      inlineError("Enter a valid email address.".localized)
      return
    }
    inFlight = true
    AuthManager.shared.sendEmailCode(email: email) { [weak self] result in
      guard let self else { return }
      self.inFlight = false
      switch result {
      case .success:
        self.resendAt = Date().addingTimeInterval(60)
        self.showCode()
      case .failure(let error): self.inlineError(error.localizedDescription)
      }
    }
  }
  private func showCode() {
    page = .code
    reset(
      "Enter your code".localized,
      subtitle: String(
        format: "Enter the six-digit code sent to %@. It expires in 10 minutes.".localized, email))
    for index in 0..<6 {
      let field = NSTextField(
        frame: NSRect(x: 140 + CGFloat(index) * 60, y: 216, width: 48, height: 52))
      styleInput(field)
      field.alignment = .center
      field.font = PanelStyle.inspectFont(ofSize: 18, weight: .semibold)
      field.delegate = self
      root.addSubview(field)
      codeFields.append(field)
    }
    codeField = codeFields.first
    button("Verify and sign in".localized, frame: NSRect(x: 140, y: 278, width: 360, height: 40)) {
      [weak self] in self?.verifyCode()
    }
    resendButton = button(
      "Resend code".localized, frame: NSRect(x: 140, y: 328, width: 360, height: 28), primary: false
    ) { [weak self] in self?.sendCode() }
    quiet("Use another email".localized, y: 368) { [weak self] in
      guard let self, let resume = self.onLogin else { return }
      self.showLogin(
        purchase: self.loginPurchase, freeWidget: self.loginFreeWidget, completion: resume)
    }
    resendTimer?.invalidate()
    updateResend()
    resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.updateResend()
    }
    makeFirstResponder(codeField)
  }
  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSTextField,
      let index = codeFields.firstIndex(of: field)
    else { return }
    let digits = field.stringValue.filter { $0 >= "0" && $0 <= "9" }
    if digits.isEmpty {
      field.stringValue = ""
      return
    }
    for (offset, digit) in digits.prefix(6 - index).enumerated() {
      codeFields[index + offset].stringValue = String(digit)
    }
    makeFirstResponder(codeFields[min(5, index + digits.count)])
  }
  private func updateResend() {
    let seconds = max(0, Int(ceil(resendAt.timeIntervalSinceNow)))
    resendButton?.isEnabled = seconds == 0
    resendButton?.title =
      seconds == 0
      ? "Resend code".localized : String(format: "Resend in %d seconds".localized, seconds)
  }
  private func verifyCode() {
    guard !inFlight else { return }
    let code = codeFields.map(\.stringValue).joined()
    guard code.count == 6, code.allSatisfy(\.isNumber) else {
      inlineError("Enter the six-digit code.".localized)
      return
    }
    inFlight = true
    AuthManager.shared.verifyEmailCode(email: email, code: code) { [weak self] result in
      self?.inFlight = false
      if case .failure(let error) = result {
        if case .server(let code, _, _) = error, code == "code_unavailable" {
          self?.showCodeUnavailable()
        } else if case .server(_, _, let remaining) = error, let remaining {
          self?.inlineError(
            String(format: "Incorrect code. %d attempts left.".localized, remaining))
          self?.updateResend()
        } else {
          self?.inlineError(error.localizedDescription)
          self?.updateResend()
        }
      }
    }
  }
  private func showCodeUnavailable() {
    showStatus(
      title: "Request a new code".localized,
      subtitle: "This code expired or has no attempts left.".localized,
      primary: "Resend code".localized, secondary: "Use another email".localized,
      onPrimary: { [weak self] in self?.sendCode() },
      onSecondary: { [weak self] in
        guard let self, let completion = self.onLogin else { return }
        self.showLogin(
          purchase: self.loginPurchase, freeWidget: self.loginFreeWidget, completion: completion)
      }, iconName: "BillingWarning",
      explanation: "One code per email every 60 seconds, up to 20 per network each hour.".localized)
    resendButton = root.subviews.compactMap { $0 as? BillingActionButton }.first(where: {
      $0.primary
    })
    updateResend()
  }
  func showPaymentHelp(_ title: String, action: @escaping () -> Void) {
    quiet(title, y: 420, action: action)
  }
  private func contactSupport(order: String? = nil) {
    guard let email = BillingManager.shared.pricing?.supportEmail, !email.isEmpty else { return }
    var link = URLComponents()
    link.scheme = "mailto"
    link.path = email
    link.queryItems = [URLQueryItem(name: "subject", value: "Glance support " + (order ?? ""))]
    if let url = link.url { NSWorkspace.shared.open(url) }
  }
  func showWallet() {
    page = .wallet
    reset(
      "Credits wallet".localized,
      subtitle: "Only cloud Widgets use credits. Local tools do not.".localized)
    let manager = BillingManager.shared
    label(
      String(manager.wallet?.balance ?? AuthManager.shared.session?.user.credits ?? 0) + " "
        + "credits".localized,
      x: 64, y: 191, width: 512, size: 48, weight: .semibold, align: .center, color: accent,
      height: 75)
    label(
      "No expiry. Shared by your Macs.".localized, x: 64, y: 272, width: 512, align: .center,
      color: secondary)
    let scroll = NSScrollView(frame: NSRect(x: 64, y: 300, width: 512, height: 160))
    let entries = manager.wallet?.transactions ?? []
    let document = Root(
      frame: NSRect(x: 0, y: 0, width: 512, height: max(160, CGFloat(entries.count) * 40)))
    for (i, entry) in entries.enumerated() {
      let date = BillingDates.display(entry.created_at)
      label(
        date + "  " + entry.label, x: 0, y: CGFloat(i) * 40 + 4, width: 414, size: 12,
        color: secondary, height: 34, parent: document)
      label(
        (entry.amount > 0 ? "+" : "") + String(entry.amount), x: 420, y: CGFloat(i) * 40 + 4,
        width: 92,
        weight: .medium, align: .right, color: entry.amount > 0 ? PanelStyle.success : ink,
        parent: document)
    }
    if entries.isEmpty {
      label(
        "No transactions yet.".localized, x: 0, y: 30, width: 512, align: .center, color: secondary,
        parent: document)
    }
    scroll.documentView = document
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    PanelStyle.styleScrollers(in: scroll)
    root.addSubview(scroll)
    primary("Top up credits".localized) { [weak self] in self?.showTopup() }
    quiet(
      pendingTaskCount > 0 ? "Return to pending task".localized : "Orders and refunds".localized
    ) { [weak self] in
      guard let self else { return }
      if self.pendingTaskCount > 0 { self.onResumeTask?() } else { self.showOrders() }
    }
    if (manager.wallet?.balance ?? 0) < 0 {
      inlineError("Paid Widgets are paused until the negative balance is cleared.".localized)
    }
  }
  func showTopup() {
    page = .topup
    guard let config = BillingManager.shared.pricing else {
      showError("Pricing is unavailable. Please try again.".localized)
      return
    }
    let balance =
      BillingManager.shared.wallet?.balance ?? AuthManager.shared.session?.user.credits ?? 0
    let cost = taskCost ?? 0
    if taskCost != nil && balance >= cost {
      reset("Ready to submit".localized, subtitle: taskName ?? "Widget")
      row("Current balance".localized, String(balance), y: 191)
      row("This task".localized, String(format: "%d credits".localized, cost), y: 231)
      primary(String(format: "Submit for %d credits".localized, cost)) { [weak self] in
        self?.onResumeTask?()
      }
      quiet("Not now".localized) { [weak self] in self?.dismiss() }
      return
    }
    reset(
      taskCost == nil
        ? "Top up credits".localized
        : String(format: "%d more credits needed".localized, max(0, cost - balance)),
      subtitle: taskCost == nil
        ? "Top up as needed. No subscription or expiry.".localized
        : String(
          format: "%@ costs %d credits. Current balance: %d. Nothing has been charged.".localized,
          taskName ?? "Widget", cost, balance))
    let packs = config.packs.filter {
      $0.enabled && $0.price(currency).amount != nil && !$0.productID.isEmpty
    }
    if !packs.contains(where: { $0.id == selectedPackID }) {
      selectedPackID =
        packs.first(where: { $0.recommended && balance + ($0.price(currency).points ?? 0) >= cost }
        )?.id
        ?? packs.first(where: { balance + ($0.price(currency).points ?? 0) >= cost })?.id
        ?? packs.max(by: { ($0.price(currency).points ?? 0) < ($1.price(currency).points ?? 0) })?
        .id
    }
    let selected = packs.first { $0.id == selectedPackID }
    var visible = Array(packs.prefix(3))
    let width: CGFloat = (512 - 24) / 3
    if let selected, !visible.contains(where: { $0.id == selected.id }), !visible.isEmpty {
      visible[visible.count - 1] = selected
    }
    for (index, pack) in visible.enumerated() {
      let price = pack.price(currency)
      let active = pack.id == selectedPackID
      let item = button(
        "", frame: NSRect(x: 64 + CGFloat(index) * (width + 12), y: 191, width: width, height: 88),
        primary: false
      ) { [weak self] in
        self?.selectedPackID = pack.id
        self?.showTopup()
      }
      (item as? BillingActionButton)?.selected = active
      (item as? BillingActionButton)?.fillColor =
        active ? NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1) : surface
      item.isEnabled = true
      label(
        String(price.points ?? 0) + " " + "credits".localized, x: item.frame.minX, y: 208,
        width: width, size: 20,
        weight: .semibold, align: .center, color: active ? accent : ink, height: 31
      ).isEnabled = item.isEnabled
      label(
        BillingManager.shared.money(price.amount, currency: currency), x: item.frame.minX, y: 246,
        width: width,
        size: 13, weight: .medium, align: .center, color: secondary)
    }
    paymentSwitch(y: 289)
    if taskCost != nil {
      let check = BillingCheckboxButton(
        checkboxWithTitle: "Automatically submit this task after credits arrive".localized,
        target: self, action: #selector(autoChanged(_:)))
      check.frame = NSRect(x: 64, y: 335, width: 512, height: 24)
      check.state = autoSubmit ? .on : .off
      check.font = PanelStyle.inspectFont(ofSize: 12)
      check.contentTintColor = ink
      root.addSubview(check)
      autoCheck = check
    }
    row(
      "Balance after top-up".localized,
      String(balance + (selected?.price(currency).points ?? 0)) + " " + "credits".localized,
      y: taskCost == nil ? 335 : 369)
    let amount = BillingManager.shared.money(selected?.price(currency).amount, currency: currency)
    primary(String(format: "Continue to payment %@".localized, amount)) { [weak self] in
      guard let self, let selected else { return }
      self.onCheckout?("credits", selected, self.currency, selected.price(self.currency))
    }
    quiet("Not now".localized) { [weak self] in self?.dismiss() }
    note("You can switch to USD card payments if WeChat Pay is unavailable.".localized)
    if selected == nil {
      inlineError("No credit packages are available yet.".localized)
      disablePrimary()
    }
    if !config.paymentsAvailable {
      inlineError("Payments are not available yet. Contact support for credits.".localized)
      disablePrimary()
    }
    if !config.paymentsAvailable && !config.supportEmail.isEmpty {
      quiet("Contact support".localized, y: 420) {
        var link = URLComponents()
        link.scheme = "mailto"
        link.path = config.supportEmail
        link.queryItems = [
          URLQueryItem(name: "subject", value: "Glance credits"),
          URLQueryItem(name: "body", value: AuthManager.shared.session?.user.email ?? ""),
        ]
        if let url = link.url { NSWorkspace.shared.open(url) }
      }
    }
    if packs.count > 3 && config.paymentsAvailable {  // Admin can add packages; keep all of them reachable.
      quiet("More packages".localized, y: 420) { [weak self] in self?.chooseMorePackages(packs) }
    }
  }
  private func chooseMorePackages(_ packs: [BillingPack]) {
    let menu = NSMenu()
    for pack in packs {
      let item = NSMenuItem(
        title:
          "\(pack.price(currency).points ?? 0) \("credits".localized) · \(BillingManager.shared.money(pack.price(currency).amount,currency:currency))",
        action: #selector(packChosen(_:)), keyEquivalent: "")
      item.representedObject = pack.id
      item.target = self
      menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: NSPoint(x: 160, y: 420), in: root)
  }
  @objc private func packChosen(_ sender: NSMenuItem) {
    selectedPackID = sender.representedObject as? String
    showTopup()
  }
  @objc private func autoChanged(_ sender: NSButton) {
    autoSubmit = sender.state == .on
    onAutoSubmitChange?(autoSubmit)
  }
  private func paymentSwitch(y: CGFloat) {
    // Figma 286:976 / 286:1018: one 512×36 track with two inset 252×28 options.
    let track = Root(frame: NSRect(x: 64, y: y, width: 512, height: 36))
    track.wantsLayer = true
    track.layer?.backgroundColor = surface.cgColor
    track.layer?.cornerRadius = 8
    track.layer?.borderWidth = 1
    track.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
    root.addSubview(track)
    for (i, currency) in ["CNY", "USD"].enumerated() {
      let label =
        currency == "CNY" ? "WeChat Pay · CNY".localized : "Card · USD".localized
      let option = button(
        label, frame: NSRect(x: 4 + CGFloat(i) * 252, y: 4, width: 252, height: 28),
        primary: false, parent: track
      ) { [weak self] in
        guard let self else { return }
        self.currency = currency
        self.selectedPackID = nil
        self.page == .topup ? self.showTopup() : self.showPro(renewal: self.returnPage == .pro)
      }
      guard let option = option as? BillingActionButton else { continue }
      option.cornerRadius = 6
      option.showsOutline = false
      option.labelSize = 12
      option.labelWeight = currency == self.currency ? .semibold : .medium
      option.labelFrame = NSRect(x: 0, y: 6, width: 252, height: 15)
      option.fillColor = currency == self.currency
        ? NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1) : surface
      option.inkColor = currency == self.currency ? accent : secondary
    }
  }
  func showPro(renewal: Bool = false) {
    page = .pro
    BillingManager.shared.track("pro_offer", feature: "pro")
    returnPage = renewal ? .pro : .account
    let manager = BillingManager.shared
    guard let config = manager.pricing else {
      showError("Pricing is unavailable. Please try again.".localized)
      return
    }
    if !renewal && (manager.hasPro || manager.entitlements?.licenseStatus == "active") {
      if manager.hasPro { showAccount() } else { showDevices() }
      return
    }
    let product = renewal ? config.renewal : config.pro
    let price = product.price(currency)
    reset(
      renewal ? "Renew feature updates".localized : "Glance Pro",
      subtitle: "Buy local tools once. Cloud Widgets use credits separately.".localized)
    label(
      renewal
        ? String(format: "%d months of feature updates".localized, config.renewalMonths)
        : "Glance Pro", x: 104, y: 191,
      width: 432,
      size: 15, weight: .semibold, align: .center)
    label(
      manager.money(price.amount, currency: currency), x: 104, y: 230, width: 432, size: 44,
      weight: .semibold, align: .center, height: 65)
    if !renewal, let cutoff = product.launchUntil,
      (BillingDates.parse(cutoff) ?? .distantPast) > Date(),
      price.amount != (currency == "CNY" ? product.CNY.amount : product.USD.amount)
    {
      let original = manager.money(
        currency == "CNY" ? product.CNY.amount : product.USD.amount, currency: currency)
      let caption = label(
        original + "  "
          + String(format: "Launch price until %@".localized, BillingDates.display(cutoff)), x: 104,
        y: 300, width: 432, align: .center, color: secondary)
      let string = NSMutableAttributedString(attributedString: caption.attributedStringValue)
      string.addAttribute(
        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
        range: NSRange(location: 0, length: (original as NSString).length))
      caption.attributedStringValue = string
    }
    row(
      "Included".localized,
      renewal ? "Feature updates".localized : "Convert, compress, export, edit".localized,
      y: 330)
    row(
      "Updates / devices".localized,
      String(
        format: "%d months / %d Macs".localized,
        renewal ? config.renewalMonths : config.updatesMonths, config.deviceLimit), y: 370)
    row(
      "Purchase gift".localized,
      renewal
        ? "None".localized
        : String(
          format: "%d credits".localized,
          manager.entitlements?.proBonusEligible == false ? 0 : config.proBonusCredits),
      y: 410)
    paymentSwitch(y: 448)
    primary(
      (renewal ? "Renew updates".localized : "Buy Pro".localized) + " · "
        + manager.money(price.amount, currency: currency)
    ) { [weak self] in
      guard let self else { return }
      self.onCheckout?(renewal ? "renewal" : "pro", nil, self.currency, price)
    }
    quiet("Not now".localized) { [weak self] in self?.dismiss() }
    if !config.paymentsAvailable || price.amount == nil || product.productID.isEmpty {
      inlineError("This product is not available yet.".localized)
      disablePrimary()
    }
  }
  func refreshAccountState() {
    if page == .account { showAccount() } else if page == .wallet { showWallet() }
  }
  func showAccount() {
    page = .account
    guard let user = AuthManager.shared.session?.user else {
      showLogin { [weak self] in self?.showAccount() }
      return
    }
    let manager = BillingManager.shared
    reset("Account and license".localized, subtitle: user.email, centered: false)
    box(x: 64, y: 191, width: 512, height: 79, color: surface, radius: 12)
    let state =
      manager.hasPro
      ? "Pro activated".localized
      : manager.remainingTrialDays > 0 ? "Trial".localized : "Free".localized
    label(
      "Glance · " + state, x: 80, y: 207, width: 480, size: 14, weight: .semibold, color: accent,
      height: 22)
    let info =
      manager.hasPro
      ? "Feature updates until".localized + " "
        + BillingDates.display(manager.verifiedClaims?.updatesUntil)
      : String(format: "Trial: %d days left".localized, manager.remainingTrialDays)
    label(info, x: 80, y: 235, width: 480, color: secondary, height: 19)
    row(
      "Active Macs".localized,
      "\(manager.entitlements?.devices.count ?? 0) / \(manager.entitlements?.deviceLimit ?? 2)",
      y: 280)
    row("Credits".localized, String(user.credits ?? 0), y: 320)
    let offlineDays =
      manager.verifiedClaims.flatMap { BillingDates.parse($0.expiresAt) }.map {
        max(0, Int(ceil($0.timeIntervalSinceNow / 86400)))
      } ?? 0
    row("Offline authorization".localized, String(format: "%d days".localized, offlineDays), y: 360)
    let links: [(String, () -> Void)] = [
      ("Orders and refunds".localized, { [weak self] in self?.showOrders() }),
      (
        manager.hasPro ? "Renew feature updates".localized : "View Pro".localized,
        { [weak self] in self?.showPro(renewal: manager.hasPro) }
      ),
      ("Sign out".localized, { [weak self] in self?.confirmSignOut() }),
    ]
    for (i, item) in links.enumerated() {
      let link = button(
        item.0, frame: NSRect(x: 64 + CGFloat(i) * 174, y: 414, width: 164, height: 28),
        primary: false, action: item.1)
      (link as? BillingActionButton)?.fillColor = .clear
    }
    button("Devices".localized, frame: NSRect(x: 304, y: 512, width: 272, height: 40)) {
      [weak self] in self?.showDevices()
    }
    button(
      "Credits wallet".localized, frame: NSRect(x: 64, y: 512, width: 224, height: 40),
      primary: false
    ) { [weak self] in
      self?.showWallet()
      BillingManager.shared.refreshWallet { _ in self?.refreshAccountState() }
    }
    if manager.entitlements?.licenseStatus == "active" && !manager.hasPro {
      note("Activate this Mac or connect to verify your Pro license.".localized)
    }
  }
  func showDevices() {
    page = .devices
    let entitlement = BillingManager.shared.entitlements
    let devices = entitlement?.devices ?? []
    reset(
      entitlement?.licenseStatus == "active" && entitlement?.pro != true
        && devices.count >= (entitlement?.deviceLimit ?? 2)
        ? "Device slots are full".localized : "Your Macs".localized,
      subtitle: String(
        format: "%d Macs per account. Device releases remaining: %d.".localized,
        entitlement?.deviceLimit ?? 2, entitlement?.releasesRemaining ?? 0), centered: false)
    back { [weak self] in self?.showAccount() }
    if !devices.contains(where: { $0.id == selectedDeviceID }) {
      selectedDeviceID = devices.last(where: { !$0.current })?.id ?? devices.first?.id
    }
    let scroll = NSScrollView(frame: NSRect(x: 64, y: 191, width: 512, height: 240))
    let document = Root(
      frame: NSRect(x: 0, y: 0, width: 512, height: max(240, CGFloat(devices.count) * 57 + 40)))
    for (index, device) in devices.enumerated() {
      let y: CGFloat = CGFloat(index) * 57
      label(
        device.name + (device.current ? " · " + "This Mac".localized : ""), x: 0, y: y, width: 512,
        size: 14, weight: .semibold, color: device.id == selectedDeviceID ? accent : ink,
        height: 22, parent: document)
      label(
        "Active".localized + " · " + BillingDates.display(device.last_seen_at), x: 0, y: y + 28,
        width: 512, color: secondary, height: 19, parent: document)
      let target = NSButton(frame: NSRect(x: 0, y: y, width: 512, height: 50))
      target.title = ""
      target.isBordered = false
      let id = UUID().uuidString
      handlers[id] = { [weak self] in
        self?.selectedDeviceID = device.id
        self?.showDevices()
      }
      target.identifier = NSUserInterfaceItemIdentifier(id)
      target.target = self
      target.action = #selector(pressed(_:))
      document.addSubview(target, positioned: .below, relativeTo: nil)
    }
    label(
      "Local files and credits".localized + " · " + "Kept".localized, x: 0,
      y: CGFloat(devices.count) * 57, width: 512, color: secondary, height: 24, parent: document)
    scroll.documentView = document
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    PanelStyle.styleScrollers(in: scroll)
    root.addSubview(scroll)
    let canActivate =
      entitlement?.licenseStatus == "active" && entitlement?.pro != true
      && devices.count < (entitlement?.deviceLimit ?? 2)
    let selected = devices.first { $0.id == selectedDeviceID }
    let action = button(
      canActivate
        ? "Activate this Mac".localized : "Release".localized + " " + (selected?.name ?? "Mac"),
      frame: NSRect(x: 304, y: 512, width: 272, height: 40)
    ) { [weak self] in
      if canActivate {
        BillingManager.shared.activateDevice { result in
          switch result {
          case .success: self?.showAccount()
          case .failure(let error): self?.inlineError(error.localizedDescription)
          }
        }
      } else if let selected {
        self?.confirmRelease(selected)
      }
    }
    action.isEnabled = canActivate || selected != nil
    button(
      "Back to account".localized, frame: NSRect(x: 64, y: 512, width: 224, height: 40),
      primary: false
    ) { [weak self] in self?.showAccount() }
  }
  private func confirmRelease(_ device: BillingDevice) {
    if (BillingManager.shared.entitlements?.releasesRemaining ?? 0) == 0 {
      showStatus(
        title: "The release limit has been reached".localized,
        subtitle: "Device releases are limited over a rolling 30 days.".localized,
        primary: "Contact support".localized, secondary: "Back to account".localized,
        onPrimary: { [weak self] in self?.contactSupport() },
        onSecondary: { [weak self] in self?.showAccount() }, iconName: "BillingWarning",
        explanation:
          "This limit prevents sharing a license among many people. Contact support if you need help."
          .localized)
      return
    }
    showStatus(
      title: "Release this Mac?".localized, subtitle: device.name,
      rows: [("Local files and credits".localized, "Kept".localized)], primary: "Release".localized,
      secondary: "Cancel".localized,
      onPrimary: { [weak self] in
        BillingManager.shared.releaseDevice(device.id) { result in
          switch result {
          case .success(let value):
            if !value.pro && !device.current {
              BillingManager.shared.activateDevice { result in
                if case .success = result {
                  self?.showStatus(
                    title: "This Mac is activated".localized,
                    subtitle: "Your files and credits are kept.".localized,
                    primary: "Done".localized, onPrimary: { [weak self] in self?.showAccount() },
                    iconName: "BillingSuccess")
                } else {
                  self?.showDevices()
                }
              }
            } else {
              self?.showDevices()
            }
          case .failure(let error): self?.showError(error.localizedDescription)
          }
        }
      }, onSecondary: { [weak self] in self?.showDevices() })
  }
  private func confirmSignOut() {
    showStatus(
      title: "Sign out?".localized,
      subtitle: "Pending task submissions will be cleared. Files and account credits are kept."
        .localized,
      primary: "Sign out".localized, secondary: "Cancel".localized,
      onPrimary: { [weak self] in
        AuthManager.shared.signOut()
        self?.dismiss()
      }, onSecondary: { [weak self] in self?.showAccount() })
  }
  func showOrders() {
    page = .orders
    reset(
      "Orders and refunds".localized,
      subtitle: "Prices are shown in the order's original currency.".localized, centered: false)
    BillingManager.shared.orders { [weak self] result in
      guard let self, self.page == .orders else { return }
      switch result {
      case .failure(let error): self.inlineError(error.localizedDescription)
      case .success(let response):
        let scroll = NSScrollView(frame: NSRect(x: 64, y: 191, width: 512, height: 280))
        let document = Root(
          frame: NSRect(
            x: 0, y: 0, width: 512, height: max(280, CGFloat(response.orders.count) * 72)))
        for (i, order) in response.orders.enumerated() {
          let y = CGFloat(i) * 72
          self.label(
            order.product.localized + " · "
              + BillingManager.shared.money(order.amount, currency: order.currency), x: 0, y: y,
            width: 380, size: 13, weight: .medium, parent: document)
          self.label(
            BillingDates.display(order.createdAt) + "  "
              + (order.refundStatus ?? order.status).localized, x: 0, y: y + 24,
            width: 380, color: self.secondary, parent: document)
          let id = UUID().uuidString
          self.handlers[id] = { [weak self] in
            if order.status == "pending" {
              self?.onResumeOrder?(order)
            } else {
              self?.showOrderDetails(order)
            }
          }
          let action = BillingActionButton(frame: NSRect(x: 392, y: y, width: 120, height: 36))
          action.title =
            order.status == "pending" ? "Continue payment".localized : "View details".localized
          action.primary = false
          action.fillColor = self.surface
          action.inkColor = self.ink
          action.identifier = NSUserInterfaceItemIdentifier(id)
          action.target = self
          action.action = #selector(self.pressed(_:))
          action.isBordered = false
          action.isEnabled = true
          document.addSubview(action)
        }
        if response.orders.isEmpty {
          self.label(
            "No orders yet.".localized, x: 0, y: 40, width: 512, align: .center,
            color: self.secondary, parent: document)
        }
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: scroll)
        self.root.addSubview(scroll)
      }
    }
    primary("Back to account".localized) { [weak self] in self?.showAccount() }
  }
  private func showOrderDetails(_ order: BillingOrder) {
    if order.status == "refunded" {
      showStatus(
        title: order.product == "pro"
          ? "Pro has been refunded".localized
          : order.product == "renewal"
            ? "Update renewal has been refunded".localized
            : "Credit top-up has been refunded".localized,
        subtitle: order.id,
        rows: [
          ("Amount".localized, BillingManager.shared.money(order.amount, currency: order.currency)),
          (
            "Current balance".localized,
            String(
              BillingManager.shared.wallet?.balance ?? AuthManager.shared.session?.user.credits ?? 0
            )
          ),
        ],
        primary: "Done".localized, onPrimary: { [weak self] in self?.showOrders() },
        iconName: "BillingSuccess")
      return
    }
    if order.refundStatus == "failed" || order.status == "refund_failed" {
      showStatus(
        title: "Refund not completed".localized,
        subtitle:
          "The payment provider could not complete the refund. Your license and credits are unchanged."
          .localized,
        primary: "Done".localized, onPrimary: { [weak self] in self?.showOrders() },
        iconName: "BillingWarning",
        explanation:
          "Support can review this order. Include its order number when contacting support."
          .localized)
      showPaymentHelp("Contact support".localized) { [weak self] in
        self?.contactSupport(order: order.id)
      }
      return
    }
    if ["requested", "processing"].contains(order.refundStatus ?? "") {
      showStatus(
        title: order.refundStatus == "requested"
          ? "Refund request submitted".localized : "Refund in progress".localized,
        subtitle: order.id, primary: "Done".localized,
        onPrimary: { [weak self] in self?.showOrders() },
        explanation: "Your entitlement changes only after the payment provider confirms the refund."
          .localized)
      return
    }
    if ["expired", "abandoned"].contains(order.status) {
      showStatus(
        title: order.status == "abandoned"
          ? "Payment abandoned".localized : "Order expired".localized,
        subtitle: "If payment was completed, it will still be credited after confirmation."
          .localized,
        primary: "Back to account".localized, onPrimary: { [weak self] in self?.showAccount() },
        iconName: "BillingWarning")
      return
    }
    let withinWindow =
      BillingDates.parse(order.paidAt).map { Date().timeIntervalSince($0) <= 14 * 86400 } ?? false
    let unused =
      order.product != "credits"
      || (BillingManager.shared.wallet?.balance ?? AuthManager.shared.session?.user.credits ?? 0)
        >= order.credits
    if !withinWindow || !unused {
      showStatus(
        title: unused
          ? "The refund window has ended".localized : "This top-up cannot be refunded".localized,
        subtitle: unused
          ? "Standard refunds are available within 14 days of payment.".localized
          : "The available balance is lower than this order's credits.".localized,
        primary: "Contact support".localized, secondary: "Back to account".localized,
        onPrimary: { [weak self] in self?.contactSupport(order: order.id) },
        onSecondary: { [weak self] in self?.showAccount() }, iconName: "BillingWarning",
        explanation:
          "Duplicate payments or undelivered purchases can be reviewed by support at any time."
          .localized)
      return
    }
    showRefund(order)
  }
  private func showRefund(_ order: BillingOrder) {
    reset(
      "Request a refund".localized,
      subtitle: "Approved refunds are returned by Pancake to the original payment method."
        .localized, centered: false)
    back { [weak self] in self?.showOrders() }
    row(
      "Order".localized,
      order.product.localized + " · "
        + BillingManager.shared.money(order.amount, currency: order.currency), y: 191)
    row("Paid on".localized, BillingDates.display(order.paidAt), y: 231)
    let cutoff = BillingDates.parse(order.paidAt).map {
      BillingDates.string($0.addingTimeInterval(14 * 86400))
    }
    row("Refund window ends".localized, BillingDates.display(cutoff), y: 271)
    label("After refund".localized, x: 64, y: 315, width: 512, size: 14, weight: .semibold)
    let description =
      order.product == "pro"
      ? String(
        format: "Pro is revoked on all Macs. The %d-credit purchase gift is recovered.".localized,
        order.bonusCredits)
      : order.product == "renewal"
        ? "Your previous feature update deadline is restored.".localized
        : String(
          format: "%d credits are recovered after the refund succeeds.".localized, order.credits)
    label(description, x: 64, y: 343, width: 512, color: secondary, height: 50)
    if order.refundStatus == "rejected", let reason = order.refundReason {
      label(
        "Refund declined".localized + ": " + reason, x: 64, y: 410, width: 512,
        color: PanelStyle.failure, height: 40)
    }
    button("Submit request".localized, frame: NSRect(x: 304, y: 512, width: 272, height: 40)) {
      [weak self] in
      BillingManager.shared.refund(order.id, reason: "Customer requested refund") { result in
        switch result {
        case .success:
          self?.showStatus(
            title: "Refund request submitted".localized, subtitle: order.id,
            primary: "Done".localized, onPrimary: { [weak self] in self?.showOrders() })
        case .failure(let error): self?.inlineError(error.localizedDescription)
        }
      }
    }
    button("Cancel".localized, frame: NSRect(x: 64, y: 512, width: 224, height: 40), primary: false)
    { [weak self] in self?.showOrders() }
  }
  private func back(_ action: @escaping () -> Void) {
    let item = button(
      "‹  " + "Back".localized, frame: NSRect(x: 24, y: 60, width: 80, height: 40), primary: false,
      action: action)
    (item as? BillingActionButton)?.fillColor = .clear
  }
  func showStatus(
    title: String, subtitle: String, rows: [(String, String)] = [], primary: String,
    secondary: String? = nil,
    onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil,
    iconName: String = "BillingStatusInfo", explanation: String? = nil
  ) {
    page = .status
    reset(title, subtitle: subtitle, status: true, iconName: iconName)
    if let explanation {
      label(
        explanation, x: 104, y: 230, width: 432, align: .center, color: self.secondary, height: 76)
    }
    for (i, item) in rows.enumerated() {
      row(item.0, item.1, y: 230 + CGFloat(i) * 40, width: 432, x: 104)
    }
    self.primary(primary, action: onPrimary)
    if let secondary, let onSecondary { quiet(secondary, action: onSecondary) }
  }
  func showError(_ message: String, retry: (() -> Void)? = nil) {
    showStatus(
      title: "Could not complete this action".localized, subtitle: message,
      primary: retry == nil ? "Done".localized : "Try again".localized,
      onPrimary: retry ?? { [weak self] in self?.dismiss() })
  }
  private func disablePrimary() {
    root.subviews.compactMap { $0 as? BillingActionButton }.filter { $0.primary }.forEach {
      $0.isEnabled = false
    }
  }
  private func openPolicy(_ kind: String) {
    let config = BillingManager.shared.pricing
    let raw =
      kind == "refunds"
      ? config?.refundURL : kind == "privacy" ? config?.privacyURL : config?.termsURL
    if let raw, let url = URL(string: raw), url.scheme == "https" { NSWorkspace.shared.open(url) }
  }
}

/// Custom drawing keeps the baseline optically centered rather than inheriting
/// NSButton's bezel baseline. All button sizes match the 640x600 Figma frames.
private final class BillingLabel: NSTextField {
  override func draw(_ dirtyRect: NSRect) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = lineBreakMode
    if let font, font.pointSize == 12 {
      paragraph.minimumLineHeight = 19
      paragraph.maximumLineHeight = 19
    }
    NSAttributedString(
      string: stringValue,
      attributes: [
        .font: font ?? PanelStyle.inspectFont(ofSize: 12),
        .foregroundColor: textColor ?? PanelStyle.textPrimary, .paragraphStyle: paragraph,
      ]
    )
    .draw(with: bounds, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class BillingActionButton: NSButton {
  var selected = false
  var primary = true
  var fillColor = NSColor.clear
  var inkColor = NSColor.labelColor
  var cornerRadius: CGFloat = 8
  var showsOutline = true
  var labelSize: CGFloat = 13
  var labelWeight: NSFont.Weight = .semibold
  /// Optional top-origin text frame for Figma-matched compact controls.
  var labelFrame: NSRect?
  override func draw(_ dirtyRect: NSRect) {
    (isHighlighted ? fillColor.withAlphaComponent(0.75) : fillColor).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    if showsOutline && !primary && fillColor != .clear {
      (selected
        ? NSColor(srgbRed: 232 / 255, green: 168 / 255, blue: 124 / 255, alpha: 0.7)
        : NSColor.white.withAlphaComponent(0.1)).setStroke()
      NSBezierPath(
        roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius,
        yRadius: cornerRadius).stroke()
    }
    let font = PanelStyle.inspectFont(ofSize: labelSize, weight: labelWeight)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byTruncatingTail
    let string = NSAttributedString(
      string: title,
      attributes: [
        .font: font, .foregroundColor: inkColor.withAlphaComponent(isEnabled ? 1 : 0.4),
        .paragraphStyle: style,
      ])
    let line = CTLineCreateWithAttributedString(string)
    let token = CTLineCreateWithAttributedString(
      NSAttributedString(string: "…", attributes: [.font: font]))
    let displayed =
      CTLineCreateTruncatedLine(line, Double(max(0, bounds.width - 16)), .end, token) ?? line
    let ink = CTLineGetImageBounds(displayed, nil)
    guard let context = NSGraphicsContext.current?.cgContext, !ink.isEmpty else { return }
    context.saveGState()
    if isFlipped {
      context.translateBy(x: 0, y: bounds.height)
      context.scaleBy(x: 1, y: -1)
    }
    context.textMatrix = .identity
    let textFrame = labelFrame ?? bounds
    context.textPosition = CGPoint(
      x: textFrame.midX - ink.midX,
      y: bounds.height - textFrame.midY - ink.midY)
    CTLineDraw(displayed, context)
    context.restoreGState()
  }
}

private final class BillingCheckboxButton: NSButton {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let rect = NSRect(x: 0, y: 4, width: 16, height: 16)
    if state == .on {
      NSImage(named: "BillingCheckbox")?.draw(in: rect)
    } else {
      NSColor.white.withAlphaComponent(0.2).setStroke()
      NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
    }
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    NSAttributedString(
      string: title,
      attributes: [
        .font: PanelStyle.inspectFont(ofSize: 12), .foregroundColor: PanelStyle.textPrimary,
        .paragraphStyle: style,
      ]
    )
    .draw(in: NSRect(x: 24, y: 4, width: bounds.width - 24, height: 18))
  }
}

private final class BillingInputCell: NSTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    let height = ceil((font?.ascender ?? 13) - (font?.descender ?? -3) + 2)
    return NSRect(
      x: rect.minX + 12, y: rect.midY - height / 2, width: max(0, rect.width - 24), height: height)
  }
  override func edit(
    withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?
  ) {
    super.edit(
      withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate,
      event: event)
  }
  override func select(
    withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start: Int,
    length: Int
  ) {
    super.select(
      withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate,
      start: start, length: length)
  }
}

final class BillingTrialBadge: NSButton {
  private var observer: NSObjectProtocol?
  init() {
    super.init(frame: .zero)
    isBordered = false
    title = ""
    target = self
    action = #selector(openPro)
    font = PanelStyle.inspectFont(ofSize: 11, weight: .medium)
    contentTintColor = PanelStyle.accent
    wantsLayer = true
    layer?.cornerRadius = 5
    layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.accent.withAlphaComponent(0.12))
    observer = NotificationCenter.default.addObserver(
      forName: BillingManager.didChange, object: nil, queue: .main
    ) { [weak self] _ in self?.refresh() }
    refresh()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  func refresh() {
    title = BillingManager.shared.trialBadge ?? ""
    isHidden = title.isEmpty
    setAccessibilityLabel(title)
  }
  @objc private func openPro() { BillingCoordinator.shared.showPro(over: window) }
}
