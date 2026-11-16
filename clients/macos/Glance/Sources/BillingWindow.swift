import AppKit
#if MAS
import AuthenticationServices
#endif
import CoreText

/// Hairline between rows (Figma `Sen · line`); borders and controls use `inspectLine` (line/strong).
private let billingLine = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)

/// Account and billing flows in the Shizuka language (Figma 36–42, 31, 34, 48).
/// The window stays a 640x600 single-column flow: it also hosts sign-in, payment
/// and confirmation steps as a sheet, so the Figma sidebar is not used.
/// Coordinates are top-origin design coordinates; the root is explicitly flipped.
final class BillingWindow: NSPanel, NSWindowDelegate, NSTextFieldDelegate {
  enum Page { case login, code, wallet, topup, pro, account, redeem, devices, orders, status }
  private final class Root: NSView { override var isFlipped: Bool { true } }
  private let root = Root(frame: NSRect(x: 0, y: 0, width: 640, height: 600))
  private var handlers: [String: () -> Void] = [:]
  private var observers: [NSObjectProtocol] = []
  private var emailField: NSTextField?
  private var codeField: NSTextField?
  private var codeFields: [NSTextField] = []
  private var reasonField: NSTextField?
  private var redemptionField: NSTextField?
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
  var taskBalance: Int?
  var requiresTaskConfirmation = false
  var taskCost: Int?
  var pendingTaskCount = 0
  var onCheckout: ((String, BillingPack?, BillingTier?, String, BillingPrice) -> Void)?
  var proJourneyID: String?
  var taskJourneyID: String?
  var taskTopupOrderID: String?
  private var selectedTierID: String?
  var onResumeTask: (() -> Void)?
  var onResumeOrder: ((BillingOrder) -> Void)?
  var onAutoSubmitChange: ((Bool) -> Void)?
  /// Content column: 512 at x 64 for account pages, 432 at x 104 for dialog-like steps.
  private var column: (x: CGFloat, width: CGFloat) = (64, 512)
  /// Top of the inline-error slot for the current page.
  private var errorY: CGFloat = 458
  /// Bottom of the flowing status content; payment help links sit below it.
  private var flowBottom: CGFloat = 420
  /// Right-aligned action row (Figma dialog footer): primary rightmost, quiet to its left.
  private var footer: [BillingActionButton] = []
  private let footerY: CGFloat = 524
  private let noteY: CGFloat = 572

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
    appearance = PanelStyle.windowAppearance
    root.wantsLayer = true
    root.layer?.backgroundColor = PanelStyle.surface.cgColor
    root.layer?.cornerRadius = PanelStyle.Radius.window
    root.layer?.masksToBounds = true
    root.layer?.borderWidth = 1
    root.layer?.borderColor = PanelStyle.inspectLine.cgColor
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
        #if MAS
        case .pro: self.showPro()  // App Store prices arrive after the page opens.
        #endif
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
    proJourneyID = nil
    resendTimer?.invalidate()
    if let parent = sheetParent { parent.endSheet(self) }
    orderOut(nil)
    onDismiss?()
  }
  func windowWillClose(_ notification: Notification) { onDismiss?() }
  override func cancelOperation(_ sender: Any?) { dismiss() }

  // MARK: - Layout primitives

  /// Clears the page and draws the title bar plus a Mincho headline and subtitle.
  /// `tone` adds the small status mark used by status steps, whose header wraps
  /// and flows; account pages keep a one-line headline so content starts at y 191.
  @discardableResult
  private func reset(
    _ title: String, subtitle: String = "", narrow: Bool = false, tone: NSColor? = nil
  ) -> CGFloat {
    root.subviews.forEach { $0.removeFromSuperview() }
    handlers.removeAll()
    emailField = nil
    codeField = nil
    codeFields.removeAll()
    reasonField = nil
    redemptionField = nil
    autoCheck = nil
    resendButton = nil
    footer.removeAll()
    column = narrow ? (104, 432) : (64, 512)
    errorY = 458
    // Figma traffic: three 12 pt line/strong dots, 20 pt apart; the first closes.
    for index in 0..<3 {
      let dot = button(
        "", frame: NSRect(x: 20 + 20 * CGFloat(index), y: 16, width: 12, height: 12), kind: .link
      ) { [weak self] in
        if index == 0 { self?.dismiss() }
      }
      dot.wantsLayer = true
      dot.layer?.backgroundColor = PanelStyle.inspectLine.cgColor
      dot.layer?.cornerRadius = 6
    }
    label(
      "Account".localized, x: 220, y: 14, width: 200, size: 13, weight: .medium, align: .center,
      color: PanelStyle.textSecondary, height: 16, lineHeight: 16)
    var titleX = column.x
    if let tone {
      mark(x: column.x, y: 106, size: 8, color: tone)
      titleX += 18
    }
    let titleWidth = column.x + column.width - titleX
    var titleHeight: CGFloat = 36
    if !title.isEmpty {
      let font: NSFont
      if tone != nil {
        font = PanelStyle.titleFont(ofSize: 28)
        titleHeight = min(72, max(36, textHeight(title, font: font, width: titleWidth, lineHeight: 36)))
      } else {
        font = fittedTitleFont(title, width: titleWidth)
      }
      label(
        title, x: titleX, y: 92, width: titleWidth, font: font, color: PanelStyle.textPrimary,
        height: titleHeight, lineHeight: 36, singleLine: tone == nil)
    }
    let subtitleY = 92 + titleHeight + 6
    var subtitleHeight: CGFloat = 0
    if !subtitle.isEmpty {
      subtitleHeight =
        tone == nil
        ? 38
        : min(76, max(19, textHeight(
          subtitle, font: PanelStyle.inspectFont(ofSize: 13), width: column.width, lineHeight: 19)))
      label(
        subtitle, x: column.x, y: subtitleY, width: column.width, size: 13,
        color: PanelStyle.textSecondary, height: subtitleHeight)
    }
    flowBottom = subtitleY + subtitleHeight
    return flowBottom
  }
  /// Mincho 28 headline that shrinks (down to 20) instead of wrapping into the content.
  private func fittedTitleFont(_ title: String, width: CGFloat) -> NSFont {
    var size: CGFloat = 28
    while size > 20 && textWidth(title, PanelStyle.titleFont(ofSize: size)) > width { size -= 1 }
    return PanelStyle.titleFont(ofSize: size)
  }
  private func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
    ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
  }
  private func textHeight(_ text: String, font: NSFont, width: CGFloat, lineHeight: CGFloat)
    -> CGFloat
  {
    guard !text.isEmpty else { return 0 }
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    let rect = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
      .boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin])
    return ceil(rect.height / lineHeight) * lineHeight
  }
  @discardableResult
  private func label(
    _ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 12,
    weight: NSFont.Weight = .regular, font: NSFont? = nil, align: NSTextAlignment = .left,
    color: NSColor? = nil, height: CGFloat = 18, lineHeight: CGFloat? = nil,
    singleLine: Bool = false, parent: NSView? = nil
  ) -> NSTextField {
    let node = BillingLabel(wrappingLabelWithString: value)
    node.font = font ?? PanelStyle.inspectFont(ofSize: size, weight: weight)
    node.textColor = color ?? PanelStyle.textPrimary
    node.alignment = align
    node.isSelectable = false
    node.lineBreakMode = .byWordWrapping
    node.lineHeight =
      lineHeight
      ?? (font != nil ? nil : [10: 14, 11: 16, 12: 18, 13: 19, 14: 20, 15: 21][size])
    if singleLine {
      node.maximumNumberOfLines = 1
      node.lineBreakMode = .byTruncatingTail
    }
    node.frame = NSRect(x: x, y: y, width: width, height: height)
    (parent ?? root).addSubview(node)
    return node
  }
  /// Small round status mark (moss success, shu failure, ai info).
  private func mark(x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, parent: NSView? = nil) {
    let view = NSView(frame: NSRect(x: x, y: y, width: size, height: size))
    view.wantsLayer = true
    view.layer?.backgroundColor = color.cgColor
    view.layer?.cornerRadius = size / 2
    (parent ?? root).addSubview(view)
  }
  private func hairline(x: CGFloat, y: CGFloat, width: CGFloat, parent: NSView? = nil) {
    let view = NSView(frame: NSRect(x: x, y: y, width: width, height: 1))
    view.wantsLayer = true
    view.layer?.backgroundColor = billingLine.cgColor
    (parent ?? root).addSubview(view)
  }
  @discardableResult
  private func button(
    _ title: String, frame: NSRect, kind: BillingActionButton.Kind = .primary,
    parent: NSView? = nil, action: @escaping () -> Void
  ) -> BillingActionButton {
    let id = UUID().uuidString
    handlers[id] = action
    let view = BillingActionButton(frame: frame)
    view.title = title
    view.identifier = NSUserInterfaceItemIdentifier(id)
    view.target = self
    view.action = #selector(pressed(_:))
    view.isBordered = false
    view.kind = kind
    (parent ?? root).addSubview(view)
    return view
  }
  @objc private func pressed(_ sender: NSButton) {
    if let key = sender.identifier?.rawValue { handlers[key]?() }
  }
  /// Text-only action (Figma "View all transactions", "Sign out").
  @discardableResult
  private func link(
    _ title: String, x: CGFloat, y: CGFloat, color: NSColor = PanelStyle.textSecondary,
    parent: NSView? = nil, action: @escaping () -> Void
  ) -> BillingActionButton {
    let node = button(title, frame: .zero, kind: .link, parent: parent, action: action)
    node.labelSize = 12
    node.inkColor = color
    node.frame = NSRect(x: x, y: y, width: node.fittingWidth, height: 24)
    return node
  }
  @discardableResult
  private func footerButton(
    _ title: String, kind: BillingActionButton.Kind, action: @escaping () -> Void
  ) -> BillingActionButton {
    let node = button(title, frame: .zero, kind: kind, action: action)
    footer.append(node)
    layoutFooter()
    return node
  }
  private func layoutFooter() {
    var right = column.x + column.width
    for node in footer.filter(\.primary) + footer.filter({ !$0.primary }) {
      let width = min(node.fittingWidth, 320)
      node.frame = NSRect(x: right - width, y: footerY, width: width, height: 32)
      right -= width + PanelStyle.Space.s
    }
  }
  private func primary(_ title: String, action: @escaping () -> Void) {
    footerButton(title, kind: .primary, action: action).isEnabled = !inFlight
  }
  /// A footer quiet button, or a text link at `y` in the content column.
  private func quiet(_ title: String, y: CGFloat? = nil, action: @escaping () -> Void) {
    if let y {
      link(title, x: column.x, y: y, action: action)
    } else {
      footerButton(title, kind: .quiet, action: action)
    }
  }
  /// Figma hairline row: text/3 name, text/1 value (mono for amounts and dates).
  private func row(
    _ name: String, _ value: String, y: CGFloat, color: NSColor? = nil, width: CGFloat = 512,
    x: CGFloat = 64, singleLine: Bool = false, mono: Bool = false
  ) {
    label(
      name, x: x, y: y + 9, width: width * 0.42, size: 13, color: PanelStyle.textTertiary,
      height: 19, singleLine: singleLine)
    label(
      value, x: x + width * 0.44, y: y + 9, width: width * 0.56, size: 13,
      font: mono ? PanelStyle.monoFont(ofSize: 13) : nil, align: .right, color: color,
      height: 19, lineHeight: 19, singleLine: singleLine)
    hairline(x: x, y: y + 35, width: width)
  }
  private func note(_ value: String) {
    label(
      value, x: column.x, y: noteY, width: column.width, size: 11,
      color: PanelStyle.textTertiary, height: 16, singleLine: true)
  }
  private func inlineError(_ message: String, footer: Bool = false) {
    root.subviews.filter { $0.identifier?.rawValue == "billing-error" }.forEach {
      $0.removeFromSuperview()
    }
    let text = footer
      ? label(message, x: column.x, y: noteY, width: column.width, size: 11,
              color: PanelStyle.failure, height: 16, singleLine: true)
      : label(
        message, x: column.x, y: errorY, width: column.width, color: PanelStyle.failure,
        height: 36)
    text.identifier = NSUserInterfaceItemIdentifier("billing-error")
    inFlight = false
    root.subviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = true }
  }
  private func styleInput(_ field: NSTextField, font: NSFont = PanelStyle.inspectFont(ofSize: 13)) {
    field.cell = BillingInputCell(textCell: field.stringValue)
    field.font = font
    field.textColor = PanelStyle.textPrimary
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.wantsLayer = true
    field.layer?.backgroundColor = PanelStyle.overlay.cgColor
    field.layer?.cornerRadius = PanelStyle.Radius.control
    field.layer?.borderWidth = 1
    field.layer?.borderColor = PanelStyle.inspectLine.cgColor
  }
  private func placeholder(_ field: NSTextField, _ text: String) {
    field.placeholderAttributedString = NSAttributedString(
      string: text,
      attributes: [
        .font: field.font ?? PanelStyle.inspectFont(ofSize: 13),
        .foregroundColor: PanelStyle.textTertiary,
      ])
  }

  // MARK: - Sign in

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
          BillingManager.shared.pricing?.signupCredits ?? 100), narrow: true)
    #if MAS
    // App Store guideline 4.8: Sign in with Apple sits above Google, at the
    // same size; everything below moves down by one button row.
    let shift: CGFloat = 44
    let apple = ASAuthorizationAppleIDButton(
      authorizationButtonType: .continue, authorizationButtonStyle: AppleSignIn.buttonStyle)
    apple.frame = NSRect(x: 104, y: 191, width: 432, height: 36)
    apple.cornerRadius = PanelStyle.Radius.control
    apple.target = self
    apple.action = #selector(signInWithApple)
    root.addSubview(apple)
    #else
    let shift: CGFloat = 0
    #endif
    button(
      "Continue with Google".localized, frame: NSRect(x: 104, y: 191 + shift, width: 432, height: 36),
      kind: .quiet
    ) {
      AuthManager.shared.openGoogleSignIn()
    }
    let divider = "Or use an email code".localized
    let dividerWidth = min(
      360, textWidth(divider, PanelStyle.inspectFont(ofSize: 11)) + 4)
    label(
      divider, x: 320 - dividerWidth / 2, y: 239 + shift, width: dividerWidth, size: 11, align: .center,
      color: PanelStyle.textTertiary, height: 16, singleLine: true)
    hairline(x: 104, y: 247 + shift, width: max(0, 216 - dividerWidth / 2 - 12))
    hairline(
      x: 320 + dividerWidth / 2 + 12, y: 247 + shift, width: max(0, 216 - dividerWidth / 2 - 12))
    label(
      "Email address".localized, x: 104, y: 263 + shift, width: 432, weight: .medium,
      color: PanelStyle.textSecondary)
    let field = NSTextField(frame: NSRect(x: 104, y: 285 + shift, width: 432, height: 44))
    styleInput(field)
    placeholder(field, "you@example.com")
    field.stringValue = email
    root.addSubview(field)
    emailField = field
    button("Send code".localized, frame: NSRect(x: 104, y: 341 + shift, width: 432, height: 36)) {
      [weak self] in self?.sendCode()
    }
    label(
      "Your image and Widget inputs are kept while you sign in.".localized, x: 104, y: 393 + shift,
      width: 432, color: PanelStyle.textTertiary, height: 36)
    let terms = link(
      "Terms of service".localized, x: 104, y: 560, color: PanelStyle.textTertiary
    ) { [weak self] in self?.openPolicy("terms") }
    link(
      "Privacy policy".localized, x: terms.frame.maxX + PanelStyle.Space.l, y: 560,
      color: PanelStyle.textTertiary
    ) { [weak self] in self?.openPolicy("privacy") }
  }
  #if MAS
  @objc private func signInWithApple() {
    guard !inFlight else { return }
    inFlight = true
    AppleSignIn.shared.start(from: self) { [weak self] result in
      guard let self else { return }
      self.inFlight = false
      // Success resumes through `.authDidChange`, like the other sign-in methods.
      if case .failure(let error) = result { self.inlineError(error.localizedDescription) }
    }
  }
  #endif
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
        format: "Enter the six-digit code sent to %@. It expires in 10 minutes.".localized, email),
      narrow: true)
    // Six 62 pt cells, 12 pt apart, filling the 432 pt column.
    for index in 0..<6 {
      let field = NSTextField(
        frame: NSRect(x: 104 + CGFloat(index) * 74, y: 191, width: 62, height: 52))
      styleInput(field, font: PanelStyle.monoFont(ofSize: 20))
      field.alignment = .center
      field.delegate = self
      root.addSubview(field)
      codeFields.append(field)
    }
    codeField = codeFields.first
    button("Verify and sign in".localized, frame: NSRect(x: 104, y: 259, width: 432, height: 36)) {
      [weak self] in self?.verifyCode()
    }
    resendButton = button(
      "Resend code".localized, frame: NSRect(x: 104, y: 303, width: 432, height: 32), kind: .quiet
    ) { [weak self] in self?.sendCode() }
    quiet("Use another email".localized, y: 347) { [weak self] in
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
    layoutFooter()
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
    quiet(title, y: flowBottom, action: action)
  }
  private func contactSupport(order: String? = nil) {
    guard let email = BillingManager.shared.pricing?.supportEmail, !email.isEmpty else { return }
    var link = URLComponents()
    link.scheme = "mailto"
    link.path = email
    link.queryItems = [URLQueryItem(name: "subject", value: "Glance support " + (order ?? ""))]
    if let url = link.url { NSWorkspace.shared.open(url) }
  }

  // MARK: - Credits

  /// Figma 36: mono eyebrow, Mincho balance, hairline transaction rows.
  func showWallet() {
    page = .wallet
    reset("")
    let manager = BillingManager.shared
    let eyebrow = label(
      "", x: 64, y: 72, width: 512, font: PanelStyle.monoFont(ofSize: 10),
      color: PanelStyle.textTertiary, height: 14, lineHeight: 14, singleLine: true)
    eyebrow.attributedStringValue = NSAttributedString(
      string: "Credits wallet".localized.uppercased(),
      attributes: [
        .font: PanelStyle.monoFont(ofSize: 10), .foregroundColor: PanelStyle.textTertiary,
        .kern: 1.5,
      ])
    let balance = String(manager.wallet?.balance ?? AuthManager.shared.session?.user.credits ?? 0)
    let balanceFont = PanelStyle.titleFont(ofSize: 56)
    let balanceWidth = min(380, textWidth(balance, balanceFont) + 2)
    label(
      balance, x: 64, y: 92, width: balanceWidth, font: balanceFont,
      color: PanelStyle.textPrimary, height: 64, lineHeight: 64, singleLine: true)
    label(
      "credits".localized, x: 64 + balanceWidth + PanelStyle.Space.m, y: 132, width: 120,
      size: 14, color: PanelStyle.textSecondary, height: 20, singleLine: true)
    let topUp = button("Top up credits".localized, frame: .zero) { [weak self] in
      self?.showTopup()
    }
    topUp.frame = NSRect(x: 576 - topUp.fittingWidth, y: 124, width: topUp.fittingWidth, height: 32)
    topUp.isEnabled = !inFlight
    label(
      "No expiry. Shared by your Macs.".localized + " "
        + "Only cloud Widgets use credits. Local tools do not.".localized,
      x: 64, y: 164, width: 512, size: 13, color: PanelStyle.textSecondary, height: 38)
    let scroll = NSScrollView(frame: NSRect(x: 64, y: 214, width: 512, height: 234))
    let entries = manager.wallet?.transactions ?? []
    let document = Root(
      frame: NSRect(x: 0, y: 0, width: 512, height: max(234, CGFloat(entries.count) * 39)))
    for (i, entry) in entries.enumerated() {
      let y = CGFloat(i) * 39
      label(
        BillingDates.display(entry.created_at), x: 0, y: y + 12, width: 100,
        font: PanelStyle.monoFont(ofSize: 11), color: PanelStyle.textTertiary, height: 16,
        lineHeight: 16, singleLine: true, parent: document)
      label(
        entry.label, x: 108, y: y + 10, width: 316, size: 13, height: 19, singleLine: true,
        parent: document)
      label(
        (entry.amount > 0 ? "+" : "") + String(entry.amount), x: 432, y: y + 10, width: 80,
        font: PanelStyle.monoFont(ofSize: 13), align: .right,
        color: entry.amount > 0 ? PanelStyle.success : PanelStyle.textPrimary, height: 19,
        lineHeight: 19, singleLine: true, parent: document)
      hairline(x: 0, y: y + 38, width: 512, parent: document)
    }
    if entries.isEmpty {
      label(
        "No transactions yet.".localized, x: 0, y: 12, width: 512, size: 13,
        color: PanelStyle.textTertiary, height: 19, parent: document)
    }
    scroll.documentView = document
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    PanelStyle.styleScrollers(in: scroll)
    root.addSubview(scroll)
    quiet(
      pendingTaskCount > 0 ? "Return to pending task".localized : "Orders and refunds".localized,
      y: 528
    ) { [weak self] in
      guard let self else { return }
      if self.pendingTaskCount > 0 { self.onResumeTask?() } else { self.showOrders() }
    }
    if (manager.wallet?.balance ?? 0) < 0 {
      inlineError("Paid Widgets are paused until the negative balance is cleared.".localized)
    }
  }
  /// Figma 41 (top-up) and 31 (price confirmation).
  func showTopup() {
    page = .topup
    guard let config = BillingManager.shared.pricing else {
      showError("Pricing is unavailable. Please try again.".localized)
      return
    }
    let balance =
      taskBalance ?? BillingManager.shared.wallet?.balance ?? AuthManager.shared.session?.user.credits ?? 0
    let cost = taskCost ?? 0
    if taskCost != nil && balance >= cost {
      reset("Ready to submit".localized, subtitle: taskName ?? "Widget")
      row("Current balance".localized, String(balance), y: 191, mono: true)
      row("This task".localized, String(format: "%d credits".localized, cost), y: 227, mono: true)
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
    errorY = 476
    #if MAS
    AppStorePurchases.shared.loadProducts(for: config)
    let packs = config.packs.filter {
      $0.enabled && ($0.price(currency).points ?? 0) > 0
        && AppStorePurchases.shared.isAvailable(AppStorePurchases.productID(pack: $0))
    }
    #else
    let packs = config.packs.filter {
      $0.enabled && $0.price(currency).amount != nil && !$0.productID.isEmpty
    }
    #endif
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
    if let selected, !visible.contains(where: { $0.id == selected.id }), !visible.isEmpty {
      visible[visible.count - 1] = selected
    }
    // Figma 28:2129: 44 pt option rows, 8 pt apart, radio + credits + price.
    for (index, pack) in visible.enumerated() {
      let price = pack.price(currency)
      let y = 191 + CGFloat(index) * 52
      let item = button("", frame: NSRect(x: 64, y: y, width: 512, height: 44), kind: .option) {
        [weak self] in
        self?.selectedPackID = pack.id
        self?.showTopup()
      }
      item.selected = pack.id == selectedPackID
      item.accessory = .radio
      label(
        String(price.points ?? 0) + " " + "credits".localized, x: 106, y: y + 12, width: 300,
        size: 14, height: 20, singleLine: true)
      label(
        priceText(pack), x: 412, y: y + 12,
        width: 148, size: 14, weight: .medium, align: .right, height: 20, singleLine: true)
    }
    if packs.count > 3 && paymentsAvailable(config) {  // Admin can add packages; keep all of them reachable.
      quiet("More packages".localized, y: 345) { [weak self] in self?.chooseMorePackages(packs) }
    }
    #if !MAS
    paymentSwitch(y: 377)  // The App Store build pays through Apple.
    #endif
    if taskCost != nil && !requiresTaskConfirmation {
      let check = BillingCheckboxButton(
        checkboxWithTitle: "Automatically submit this task after credits arrive".localized,
        target: self, action: #selector(autoChanged(_:)))
      check.frame = NSRect(x: 64, y: 405, width: 512, height: 24)
      check.state = autoSubmit ? .on : .off
      check.font = PanelStyle.inspectFont(ofSize: 12)
      root.addSubview(check)
      autoCheck = check
    }
    let balanceY: CGFloat = taskCost == nil ? 405 : 433
    hairline(x: 64, y: balanceY, width: 512)
    row(
      "Balance after top-up".localized,
      String(balance + (selected?.price(currency).points ?? 0)) + " " + "credits".localized,
      y: balanceY, mono: true)
    let amount = selected.map(priceText) ?? BillingManager.shared.money(nil, currency: currency)
    primary(String(format: "Continue to payment %@".localized, amount)) { [weak self] in
      guard let self, let selected else { return }
      self.onCheckout?("credits", selected, nil, self.currency, selected.price(self.currency))
    }
    quiet("Not now".localized) { [weak self] in self?.dismiss() }
    #if !MAS
    note("You can switch to USD card payments if WeChat Pay is unavailable.".localized)
    #endif
    if selected == nil {
      inlineError("No credit packages are available yet.".localized)
      disablePrimary()
    }
    if !paymentsAvailable(config) {
      inlineError("Payments are not available yet. Contact support for credits.".localized)
      disablePrimary()
    }
    if !paymentsAvailable(config) && !config.supportEmail.isEmpty {
      quiet("Contact support".localized) {
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
  }
  /// A pack's price: Apple's storefront price in the App Store build.
  private func priceText(_ pack: BillingPack) -> String {
    #if MAS
    return AppStorePurchases.shared.displayPrice(AppStorePurchases.productID(pack: pack))
      ?? BillingManager.shared.money(nil, currency: currency)
    #else
    return BillingManager.shared.money(pack.price(currency).amount, currency: currency)
    #endif
  }
  /// The App Store build is purchasable whenever Apple returns the product.
  private func paymentsAvailable(_ config: BillingPricing) -> Bool {
    #if MAS
    return true
    #else
    return config.paymentsAvailable
    #endif
  }
  private func chooseMorePackages(_ packs: [BillingPack]) {
    let menu = NSMenu()
    for pack in packs {
      let item = NSMenuItem(
        title:
          "\(pack.price(currency).points ?? 0) \("credits".localized) · \(priceText(pack))",
        action: #selector(packChosen(_:)), keyEquivalent: "")
      item.representedObject = pack.id
      item.target = self
      menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: NSPoint(x: 64, y: 369), in: root)
  }
  @objc private func packChosen(_ sender: NSMenuItem) {
    selectedPackID = sender.representedObject as? String
    showTopup()
  }
  @objc private func autoChanged(_ sender: NSButton) {
    autoSubmit = sender.state == .on
    onAutoSubmitChange?(autoSubmit)
  }
  @objc private func cardCurrencyChosen(_ sender: NSMenuItem) {
    guard let code = sender.representedObject as? String else { return }
    currency = code; selectedPackID = nil
    page == .topup ? showTopup() : showPro()
  }
  /// "Pay with" followed by two outlined option buttons (28 pt): the active one
  /// carries the text/1 outline. Card opens a currency menu, hence the chevron.
  private func paymentSwitch(y: CGFloat, x: CGFloat = 64) {
    let caption = "Pay with".localized
    let captionWidth = textWidth(caption, PanelStyle.inspectFont(ofSize: 12)) + 2
    label(
      caption, x: x, y: y + 1, width: captionWidth, color: PanelStyle.textTertiary,
      singleLine: true)
    var optionX = x + captionWidth + PanelStyle.Space.l
    for currency in ["CNY", self.currency == "CNY" ? "USD" : self.currency] {
      let title =
        currency == "CNY" ? "WeChat Pay · CNY".localized : "Card".localized + " · " + currency + "  ▾"
      let option = button(title, frame: .zero, kind: .option) { [weak self] in
        guard let self else { return }
        if currency == "CNY" {
          self.currency = currency
          self.selectedPackID = nil
          self.page == .topup ? self.showTopup() : self.showPro()
        } else {
          let menu = NSMenu()
          for code in ["USD", "JPY", "EUR", "HKD"] {
            let item = NSMenuItem(title: code, action: #selector(self.cardCurrencyChosen(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = code
            item.state = code == self.currency ? .on : .off
            menu.addItem(item)
          }
          menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
      }
      option.selected = currency == self.currency
      option.labelSize = 12
      option.labelWeight = option.selected ? .medium : .regular
      option.inkColor = option.selected ? PanelStyle.textPrimary : PanelStyle.textSecondary
      // Centred on the 20 pt caption line; label plus 12 pt padding each side.
      option.frame = NSRect(x: optionX, y: y - 4, width: option.fittingWidth + 20, height: 28)
      optionX += option.frame.width + PanelStyle.Space.s
    }
  }

  // MARK: - Pro

  /// Pro offer: a lifetime licence sold in tiers by number of Macs. With Pro
  /// already active only larger tiers are offered, as an upgrade. Figma 37.
  func showPro() {
    page = .pro
    returnPage = .account
    let manager = BillingManager.shared
    guard let config = manager.pricing else {
      showError("Pricing is unavailable. Please try again.".localized)
      return
    }
    if proJourneyID == nil {
      proJourneyID = UUID().uuidString
      manager.track("pro_offer", journeyID: proJourneyID, feature: "pro")
    }
    if manager.entitlements?.licenseStatus == "active" && !manager.hasPro {
      showDevices()
      return
    }
    let tiers = manager.purchasableTiers
    guard !tiers.isEmpty else { showAccount(); return }
    let upgrade = manager.hasPro
    if !tiers.contains(where: { $0.id == selectedTierID }) {
      selectedTierID = (tiers.first { $0.recommended } ?? tiers[0]).id
    }
    let tier = tiers.first { $0.id == selectedTierID } ?? tiers[0]
    let price = tier.price(currency, launchUntil: config.launchUntil)
    reset(
      upgrade ? "Upgrade Pro".localized : "Glance Pro",
      subtitle: "Buy local tools once. Cloud Widgets use credits separately.".localized)
    tierCards(tiers, y: 186)
    #if MAS
    AppStorePurchases.shared.loadProducts(for: config)
    let storePrice = AppStorePurchases.shared.displayPrice(AppStorePurchases.productID(tier: tier))
    #endif
    // Launch discounts come from the web price list; the App Store sets its own prices.
    #if !MAS
    if let amount = price.amount {
      let regular = tier.regularPrice(currency)
      let discounted = regular.amount != nil && regular.amount != amount
      if discounted, let cutoff = config.launchUntil {
        let original = manager.money(regular.amount, currency: currency)
        let caption = label(
          original + "  " + String(format: "Launch price until %@".localized, BillingDates.display(cutoff)),
          x: 64, y: 304, width: 512, color: PanelStyle.textTertiary, singleLine: true)
        let string = NSMutableAttributedString(attributedString: caption.attributedStringValue)
        string.addAttribute(
          .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
          range: NSRange(location: 0, length: (original as NSString).length))
        caption.attributedStringValue = string
      }
    }
    #endif
    row("Included".localized, "All features".localized, y: 326, singleLine: true)
    row(
      "Macs / updates".localized,
      tier.seatLabel + " · " + "Lifetime, free".localized, y: 362, singleLine: true)
    row(
      "Purchase gift".localized,
      String(
        format: "%d credits".localized,
        upgrade || manager.entitlements?.proBonusEligible == false ? 0 : config.proBonusCredits),
      y: 398, singleLine: true, mono: true)
    #if !MAS
    paymentSwitch(y: 446)
    #endif
    if !upgrade && manager.remainingTrialDays > 0 {
      label(
        String(format: "Trial: %d days left".localized, manager.remainingTrialDays), x: 64,
        y: footerY + 7, width: 180, color: PanelStyle.textSecondary, singleLine: true)
    }
    #if MAS
    let priceSuffix = storePrice.map { " · " + $0 } ?? ""
    #else
    let priceSuffix = price.amount == nil ? "" : " · " + manager.money(price.amount, currency: currency)
    #endif
    primary((upgrade ? "Upgrade".localized : "Buy Pro".localized) + priceSuffix) { [weak self] in
      guard let self else { return }
      self.onCheckout?("pro", nil, tier, self.currency, price)
    }
    quiet("Not now".localized) { [weak self] in self?.dismiss() }
    // Signed out, the button leads to sign-in and the refreshed, per-account
    // offer (the owner's test account gets mock checkout), so it stays enabled.
    #if MAS
    let unavailable = storePrice == nil
    #else
    let unavailable = !config.paymentsAvailable || price.amount == nil || tier.productID.isEmpty
    #endif
    if AuthManager.shared.isSignedIn && unavailable {
      inlineError("This product is not available yet.".localized, footer: true)
      disablePrimary()
    } else if config.mockCheckout == true {
      note("Simulated payment for testing. No money is charged.".localized)
    }
  }
  /// Figma 28:1666: one card per tier (name, Mincho price, seats); the selected
  /// tier has a text/1 outline and a check. A single tier is shown as a plain card.
  private func tierCards(_ tiers: [BillingTier], y: CGFloat) {
    guard let config = BillingManager.shared.pricing else { return }
    let gap = PanelStyle.Space.m
    let width = (512 - gap * CGFloat(tiers.count - 1)) / CGFloat(tiers.count)
    for (i, tier) in tiers.enumerated() {
      let x = 64 + CGFloat(i) * (width + gap)
      let frame = NSRect(x: x, y: y, width: width, height: 108)
      if tiers.count > 1 {
        let card = button("", frame: frame, kind: .option) { [weak self] in
          guard let self else { return }
          self.selectedTierID = tier.id
          self.showPro()
        }
        card.selected = tier.id == selectedTierID
        card.accessory = card.selected ? .check : .none
      } else {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = PanelStyle.Radius.control
        card.layer?.borderWidth = 1
        card.layer?.borderColor = PanelStyle.inspectLine.cgColor
        root.addSubview(card)
      }
      #if MAS
      let priceLabel = AppStorePurchases.shared.displayPrice(AppStorePurchases.productID(tier: tier))
      #else
      let amount = tier.price(currency, launchUntil: config.launchUntil).amount
      let priceLabel = amount.map { BillingManager.shared.money($0, currency: currency) }
      #endif
      label(
        tier.localizedName, x: x + 16, y: y + 16, width: width - 52, size: 13, weight: .medium,
        height: 19, singleLine: true)
      if let priceLabel {
        label(
          priceLabel, x: x + 16, y: y + 40,
          width: width - 32, font: PanelStyle.titleFont(ofSize: 26), height: 34, lineHeight: 34,
          singleLine: true)
      }
      label(
        tier.seatLabel, x: x + 16, y: y + 78, width: width - 32, color: PanelStyle.textTertiary,
        singleLine: true)
    }
  }

  // MARK: - Account

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
    reset("Account and license".localized, subtitle: user.email)
    let state =
      manager.hasPro
      ? "Pro activated".localized
      : manager.remainingTrialDays > 0 ? "Trial".localized : "Free".localized
    mark(
      x: 64, y: 199, size: 6,
      color: manager.hasPro
        ? PanelStyle.success : manager.remainingTrialDays > 0 ? PanelStyle.info : PanelStyle.textTertiary)
    label(
      "Glance · " + state, x: 78, y: 191, width: 498, size: 15, weight: .medium, height: 21,
      singleLine: true)
    let info =
      manager.hasPro
      ? String(format: "%d Macs".localized, manager.entitlements?.deviceLimit ?? 1) + " · "
        + manager.licenseDurationLabel
      : String(format: "Trial: %d days left".localized, manager.remainingTrialDays)
    label(info, x: 78, y: 214, width: 498, color: PanelStyle.textSecondary, singleLine: true)
    row(
      "Active Macs".localized,
      "\(manager.entitlements?.devices.count ?? 0) / \(manager.entitlements?.deviceLimit ?? 2)",
      y: 244, mono: true)
    row("Credits".localized, String(user.credits ?? 0), y: 280, mono: true)
    let offlineDays =
      manager.verifiedClaims.flatMap { BillingDates.parse($0.expiresAt) }.map {
        max(0, Int(ceil($0.timeIntervalSinceNow / 86400)))
      } ?? 0
    row(
      "Offline authorization".localized, String(format: "%d days".localized, offlineDays), y: 316,
      mono: true)
    var links: [(String, () -> Void)] = [
      ("Orders and refunds".localized, { [weak self] in self?.showOrders() })
    ]
    if !manager.hasPro {
      links.append(("View Pro".localized, { [weak self] in self?.showPro() }))
    } else if !manager.purchasableTiers.isEmpty {
      links.append(("Add Macs".localized, { [weak self] in self?.showPro() }))
    }
    links.append(("Sign out".localized, { [weak self] in self?.confirmSignOut() }))
    var linkX: CGFloat = 64
    for item in links {
      let node = link(item.0, x: linkX, y: 368, color: PanelStyle.textPrimary, action: item.1)
      linkX = node.frame.maxX + PanelStyle.Space.xl
    }
    if !manager.hasPro {
      quiet("Redeem a code".localized, y: 400) { [weak self] in self?.showRedeemCode() }
    }
    footerButton("Devices".localized, kind: .primary) { [weak self] in self?.showDevices() }
    footerButton("Credits wallet".localized, kind: .quiet) { [weak self] in
      self?.showWallet()
      BillingManager.shared.refreshWallet { _ in self?.refreshAccountState() }
    }
    if manager.entitlements?.licenseStatus == "active" && !manager.hasPro {
      note("Activate this Mac or connect to verify your Pro license.".localized)
    }
  }
  /// Figma 42: field, explanation, right-aligned action.
  private func showRedeemCode() {
    page = .redeem
    reset(
      "Redeem Pro".localized,
      subtitle: "Enter your Pro redemption code. Cloud Widget credits are not included.".localized,
      narrow: true)
    errorY = 339
    back { [weak self] in self?.showAccount() }
    let field = NSTextField(frame: NSRect(x: 104, y: 191, width: 432, height: 44))
    styleInput(field, font: PanelStyle.monoFont(ofSize: 14))
    placeholder(field, "GLG-XXXX-XXXX-XXXX-XXXX")
    root.addSubview(field)
    redemptionField = field
    label(
      "Lifetime and one-year codes unlock local Pro tools. Your files and credits stay unchanged.".localized,
      x: 104, y: 247, width: 432, color: PanelStyle.textTertiary, height: 36)
    let redeem = button("Redeem Pro".localized, frame: .zero) { [weak self] in
      self?.submitRedemptionCode()
    }
    redeem.frame = NSRect(
      x: 536 - redeem.fittingWidth, y: 295, width: redeem.fittingWidth, height: 32)
    makeFirstResponder(field)
  }
  private func submitRedemptionCode() {
    guard !inFlight else { return }
    let code = redemptionField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !code.isEmpty else {
      inlineError("Enter a redemption code.".localized)
      return
    }
    inFlight = true
    disablePrimary()
    BillingManager.shared.redeemProCode(code) { [weak self] result in
      guard let self else { return }
      self.inFlight = false
      switch result {
      case .failure(let error): self.inlineError(error.localizedDescription)
      case .success(let value):
        let activated = BillingManager.shared.hasPro
        let duration = value.accessExpiresAt.map {
          String(format: "Pro until %@".localized, BillingDates.display($0))
        } ?? "Lifetime Pro".localized
        let subtitle = activated
          ? "Your files and credits are unchanged.".localized
          : "Your files and credits are unchanged. Activate this Mac from Devices.".localized
        self.showStatus(
          title: activated ? "Pro activated".localized : "Code redeemed".localized,
          subtitle: subtitle, rows: [("License".localized, duration)], primary: "Back to account".localized,
          secondary: activated ? nil : "Devices".localized,
          onPrimary: { [weak self] in self?.showAccount() },
          onSecondary: activated ? nil : { [weak self] in self?.showDevices() }, iconName: "BillingSuccess")
      }
    }
  }

  // MARK: - Devices

  /// Figma 38: device rows; the selected row (release target) has a text/1 outline.
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
        entitlement?.deviceLimit ?? 2, entitlement?.releasesRemaining ?? 0))
    back { [weak self] in self?.showAccount() }
    if !devices.contains(where: { $0.id == selectedDeviceID }) {
      selectedDeviceID = devices.last(where: { !$0.current })?.id ?? devices.first?.id
    }
    let scroll = NSScrollView(frame: NSRect(x: 64, y: 191, width: 512, height: 252))
    let document = Root(
      frame: NSRect(x: 0, y: 0, width: 512, height: max(252, CGFloat(devices.count) * 56 + 40)))
    let nameFont = PanelStyle.inspectFont(ofSize: 14, weight: .medium)
    for (index, device) in devices.enumerated() {
      let y: CGFloat = CGFloat(index) * 56
      let item = button(
        "", frame: NSRect(x: 0, y: y, width: 512, height: 50), kind: .row, parent: document
      ) { [weak self] in
        self?.selectedDeviceID = device.id
        self?.showDevices()
      }
      item.selected = device.id == selectedDeviceID
      let tag = "This Mac".localized
      let tagWidth = device.current ? textWidth(tag, PanelStyle.inspectFont(ofSize: 11)) + 2 : 0
      let nameWidth = min(textWidth(device.name, nameFont) + 2, 488 - tagWidth - 8)
      label(
        device.name, x: 12, y: y + 7, width: nameWidth, font: nameFont, height: 20,
        lineHeight: 20, singleLine: true, parent: document)
      if device.current {
        label(
          tag, x: 12 + nameWidth + 8, y: y + 9, width: tagWidth, size: 11,
          color: PanelStyle.success, height: 16, singleLine: true, parent: document)
      }
      label(
        "Active".localized + " · " + BillingDates.display(device.last_seen_at), x: 12,
        y: y + 28, width: 488, color: PanelStyle.textTertiary, singleLine: true, parent: document)
    }
    label(
      "Local files and credits".localized + " · " + "Kept".localized, x: 0,
      y: CGFloat(devices.count) * 56 + 8, width: 512, color: PanelStyle.textTertiary,
      singleLine: true, parent: document)
    scroll.documentView = document
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    PanelStyle.styleScrollers(in: scroll)
    root.addSubview(scroll)
    let canActivate =
      entitlement?.licenseStatus == "active" && entitlement?.pro != true
      && devices.count < (entitlement?.deviceLimit ?? 2)
    let selected = devices.first { $0.id == selectedDeviceID }
    let action = footerButton(
      canActivate
        ? "Activate this Mac".localized : "Release".localized + " " + (selected?.name ?? "Mac"),
      kind: .primary
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
    footerButton("Back to account".localized, kind: .quiet) { [weak self] in self?.showAccount() }
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

  // MARK: - Orders and refunds

  /// Figma 39: hairline table of date, item, amount, status and a text action.
  func showOrders() {
    page = .orders
    reset(
      "Orders and refunds".localized,
      subtitle: "Prices are shown in the order's original currency.".localized)
    BillingManager.shared.orders { [weak self] result in
      guard let self, self.page == .orders else { return }
      switch result {
      case .failure(let error): self.inlineError(error.localizedDescription)
      case .success(let response):
        let scroll = NSScrollView(frame: NSRect(x: 64, y: 191, width: 512, height: 310))
        let document = Root(
          frame: NSRect(
            x: 0, y: 0, width: 512, height: max(310, CGFloat(response.orders.count) * 44)))
        for (i, order) in response.orders.enumerated() {
          let y = CGFloat(i) * 44
          let status = order.refundStatus ?? order.status
          self.label(
            BillingDates.display(order.createdAt), x: 0, y: y + 14, width: 88,
            font: PanelStyle.monoFont(ofSize: 11), color: PanelStyle.textTertiary, height: 16,
            lineHeight: 16, singleLine: true, parent: document)
          self.label(
            order.product.localized, x: 92, y: y + 12, width: 120, size: 13, height: 19,
            singleLine: true, parent: document)
          self.label(
            BillingManager.shared.money(order.amount, currency: order.currency), x: 216,
            y: y + 13, width: 84, font: PanelStyle.monoFont(ofSize: 12), height: 18,
            lineHeight: 18, singleLine: true, parent: document)
          self.label(
            status.localized, x: 304, y: y + 13, width: 100,
            color: ["refunded"].contains(status)
              ? PanelStyle.success
              : ["requested", "processing"].contains(status)
                ? PanelStyle.info
                : ["failed", "refund_failed"].contains(status)
                  ? PanelStyle.failure : PanelStyle.textSecondary,
            singleLine: true, parent: document)
          let action = self.link(
            order.status == "pending" ? "Continue payment".localized : "View details".localized,
            x: 0, y: y + 10, color: PanelStyle.textPrimary, parent: document
          ) { [weak self] in
            if order.status == "pending" {
              self?.onResumeOrder?(order)
            } else {
              self?.showOrderDetails(order)
            }
          }
          action.frame = NSRect(
            x: 512 - min(104, action.frame.width), y: y + 10, width: min(104, action.frame.width),
            height: 24)
          action.isEnabled = true
          self.hairline(x: 0, y: y + 43, width: 512, parent: document)
        }
        if response.orders.isEmpty {
          self.label(
            "No orders yet.".localized, x: 0, y: 12, width: 512, size: 13,
            color: PanelStyle.textTertiary, height: 19, parent: document)
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
    if order.store == "app_store" {
      // Apple refunds App Store purchases; the service removes the purchase
      // when Apple's refund notification arrives.
      showStatus(
        title: "Refunds are handled by Apple".localized,
        subtitle: "Request a refund from Apple. Once Apple approves it, Glance removes this purchase automatically.".localized,
        primary: "Request a refund from Apple".localized, secondary: "Back to account".localized,
        onPrimary: { NSWorkspace.shared.open(URL(string: "https://reportaproblem.apple.com")!) },
        onSecondary: { [weak self] in self?.showAccount() })
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
        .localized)
    back { [weak self] in self?.showOrders() }
    row(
      "Order".localized,
      order.product.localized + " · "
        + BillingManager.shared.money(order.amount, currency: order.currency), y: 191,
      singleLine: true)
    row("Paid on".localized, BillingDates.display(order.paidAt), y: 227, mono: true)
    let cutoff = BillingDates.parse(order.paidAt).map {
      BillingDates.string($0.addingTimeInterval(14 * 86400))
    }
    row("Refund window ends".localized, BillingDates.display(cutoff), y: 263, mono: true)
    label(
      "After refund".localized, x: 64, y: 315, width: 512, size: 13, weight: .medium, height: 19)
    let description =
      order.product == "pro"
      ? String(
        format: "Pro is revoked on all Macs. The %d-credit purchase gift is recovered.".localized,
        order.bonusCredits)
      : order.product == "renewal"
        ? "Your previous feature update deadline is restored.".localized
        : String(
          format: "%d credits are recovered after the refund succeeds.".localized, order.credits)
    label(
      description, x: 64, y: 338, width: 512, size: 13, color: PanelStyle.textSecondary,
      height: 57)
    if order.refundStatus == "rejected", let reason = order.refundReason {
      mark(x: 64, y: 412, size: 6, color: PanelStyle.failure)
      label(
        "Refund declined".localized + ": " + reason, x: 78, y: 405, width: 498,
        color: PanelStyle.failure, height: 36)
    }
    footerButton("Submit request".localized, kind: .primary) { [weak self] in
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
    footerButton("Cancel".localized, kind: .quiet) { [weak self] in self?.showOrders() }
  }
  private func back(_ action: @escaping () -> Void) {
    link("‹  " + "Back".localized, x: 16, y: 52, action: action)
  }

  // MARK: - Status

  /// Confirmation / result step (Figma 48 dialogs, 34 task-state marks): a small
  /// tone mark, wrapping Mincho title, hairline rows, explanation, footer actions.
  func showStatus(
    title: String, subtitle: String, rows: [(String, String)] = [], primary: String,
    secondary: String? = nil,
    onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil,
    iconName: String = "BillingStatusInfo", explanation: String? = nil
  ) {
    page = .status
    let tone =
      iconName == "BillingWarning"
      ? PanelStyle.failure
      : iconName == "BillingSuccess"
        ? PanelStyle.success : iconName == "BillingTasks" ? PanelStyle.info : PanelStyle.textTertiary
    var y = reset(title, subtitle: subtitle, narrow: true, tone: tone) + 20
    for (i, item) in rows.enumerated() {
      self.row(
        item.0, item.1, y: y + CGFloat(i) * 36, width: 432, x: 104, singleLine: true,
        mono: item.1.contains(where: \.isNumber))
    }
    if !rows.isEmpty { y += CGFloat(rows.count) * 36 + 16 }
    if let explanation {
      let height = min(76, textHeight(
        explanation, font: PanelStyle.inspectFont(ofSize: 12), width: 432, lineHeight: 18))
      label(
        explanation, x: 104, y: y, width: 432, color: PanelStyle.textSecondary, height: height)
      y += height + 16
    }
    flowBottom = min(y, 488)
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

/// Draws its text top-aligned at a fixed line height so the frame stays 1:1
/// with the Figma text node, independent of font baseline metrics.
private final class BillingLabel: NSTextField {
  var lineHeight: CGFloat?
  override func draw(_ dirtyRect: NSRect) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = lineBreakMode
    if let lineHeight {
      paragraph.minimumLineHeight = lineHeight
      paragraph.maximumLineHeight = lineHeight
    }
    // Start from the attributed value so ranges such as the launch-price
    // strikethrough or eyebrow tracking survive; font, colour and paragraph apply to the whole string.
    let text = NSMutableAttributedString(attributedString: attributedStringValue)
    text.addAttributes(
      [
        .font: font ?? PanelStyle.inspectFont(ofSize: 12),
        .foregroundColor: textColor ?? PanelStyle.textPrimary, .paragraphStyle: paragraph,
      ], range: NSRange(location: 0, length: text.length))
    text.draw(with: bounds, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Shizuka buttons: primary = accent fill + accentInk; quiet = line/strong
/// hairline; option/row = selectable with a text/1 outline (no fill); link and
/// segment are text only. Labels are drawn optically centred from glyph bounds.
private final class BillingActionButton: NSButton {
  enum Kind { case primary, quiet, link, segment, option, row }
  enum Accessory { case none, radio, check }
  var kind = Kind.primary { didSet { needsDisplay = true } }
  var selected = false { didSet { needsDisplay = true } }
  var accessory = Accessory.none { didSet { needsDisplay = true } }
  var primary: Bool { kind == .primary }
  var inkColor: NSColor?
  var labelSize: CGFloat = 13
  var labelWeight: NSFont.Weight = .medium
  private var labelFont: NSFont { PanelStyle.inspectFont(ofSize: labelSize, weight: labelWeight) }
  /// Figma button width: label plus 16 pt padding each side; text actions hug the label.
  var fittingWidth: CGFloat {
    let width = ceil(NSAttributedString(string: title, attributes: [.font: labelFont]).size().width)
    switch kind {
    case .primary, .quiet: return max(64, width + 32)
    default: return width + 4
    }
  }
  private var ink: NSColor {
    if let inkColor { return inkColor }
    switch kind {
    case .primary: return PanelStyle.accentInk
    case .link: return PanelStyle.textSecondary
    case .segment: return selected ? PanelStyle.textPrimary : PanelStyle.textTertiary
    default: return PanelStyle.textPrimary
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.setAlpha(isEnabled ? 1 : 0.4)
    let radius = PanelStyle.Radius.control
    let fill = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    let outline = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    outline.lineWidth = 1
    switch kind {
    case .primary:
      (isHighlighted ? PanelStyle.accentHover : PanelStyle.accent).setFill()
      fill.fill()
    case .quiet, .option, .row:
      if isHighlighted {
        PanelStyle.controlFill.setFill()
        fill.fill()
      }
      if selected {
        PanelStyle.textPrimary.setStroke()
        outline.stroke()
      } else if kind == .row {
        billingLine.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.height - 1 : 0, width: bounds.width, height: 1).fill()
      } else {
        PanelStyle.inspectLine.setStroke()
        outline.stroke()
      }
    case .link, .segment:
      break
    }
    drawAccessory()
    drawTitle(in: context)
  }
  /// Top-origin rect converted to this view's coordinate space.
  private func rect(top: CGFloat, x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: isFlipped ? top : bounds.height - top - height, width: width, height: height)
  }
  private func drawAccessory() {
    switch accessory {
    case .none: break
    case .radio:
      // Figma 28:2130: 14 pt radio, 16 pt from the leading edge, vertically centred.
      let dot = rect(top: (bounds.height - 14) / 2, x: 16, width: 14, height: 14)
      if selected {
        PanelStyle.textPrimary.setFill()
        NSBezierPath(ovalIn: dot).fill()
      } else {
        PanelStyle.textTertiary.setStroke()
        let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
      }
    case .check:
      // Figma 28:1678: 16 pt check at the card's top-right, 16 pt inset.
      let box = rect(top: 16, x: bounds.width - 32, width: 16, height: 16)
      let path = NSBezierPath()
      let point = { (x: CGFloat, y: CGFloat) -> NSPoint in
        NSPoint(x: box.minX + x, y: self.isFlipped ? box.minY + y : box.maxY - y)
      }
      path.move(to: point(3, 8.5))
      path.line(to: point(6.5, 12))
      path.line(to: point(13, 4.5))
      path.lineWidth = 1.5
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      PanelStyle.textPrimary.setStroke()
      path.stroke()
    }
  }
  private func drawTitle(in context: CGContext) {
    guard !title.isEmpty else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byTruncatingTail
    let color = isHighlighted && (kind == .link || kind == .segment) ? ink.withAlphaComponent(0.7) : ink
    let string = NSAttributedString(
      string: title,
      attributes: [.font: labelFont, .foregroundColor: color, .paragraphStyle: style])
    let line = CTLineCreateWithAttributedString(string)
    let token = CTLineCreateWithAttributedString(
      NSAttributedString(string: "…", attributes: [.font: labelFont]))
    let inset: CGFloat = kind == .primary || kind == .quiet ? 16 : 0
    let displayed =
      CTLineCreateTruncatedLine(line, Double(max(0, bounds.width - inset * 2)), .end, token) ?? line
    let ink = CTLineGetImageBounds(displayed, nil)
    guard !ink.isEmpty else { return }
    context.saveGState()
    if isFlipped {
      context.translateBy(x: 0, y: bounds.height)
      context.scaleBy(x: 1, y: -1)
    }
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
    CTLineDraw(displayed, context)
    context.restoreGState()
  }
}

private final class BillingCheckboxButton: NSButton {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let rect = NSRect(x: 0, y: 4, width: 16, height: 16)
    let radius = PanelStyle.Radius.thumb
    if state == .on {
      PanelStyle.textPrimary.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      let check = NSBezierPath()
      check.move(to: NSPoint(x: rect.minX + 4, y: rect.minY + 8.5))
      check.line(to: NSPoint(x: rect.minX + 7, y: rect.minY + 11.5))
      check.line(to: NSPoint(x: rect.minX + 12.5, y: rect.minY + 5))
      check.lineWidth = 1.5
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      PanelStyle.accentInk.setStroke()
      check.stroke()
    } else {
      PanelStyle.inspectLine.setStroke()
      NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        .stroke()
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
