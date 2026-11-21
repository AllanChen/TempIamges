using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using Glance.App.Localization;
using Glance.App.Theme;
using Glance.App.Windows;
using Glance.Core.Account;
using Glance.Core.Billing;
using Glance.Core.Logging;
using Glance.Core.Widgets;
using Glance.Platform;

namespace Glance.App.Account;

/// <summary>
/// Sign-in, credits wallet and top-up (port of the macOS <c>BillingWindow</c> pages the Windows
/// client needs: login, code, wallet, top-up, payment, status, sign-out). A 640 × 600 sheet; the
/// login column is 432 wide (x 104), account pages 512 (x 64). Purchases go through the browser
/// checkout; balance changes always come from the service, never from a return URL.
/// </summary>
internal sealed class AccountWindow : Window
{
    private const double SheetWidth = 640;
    private const double SheetHeight = 600;
    private const int ResendSeconds = 60;
    private static readonly TimeSpan PaymentPoll = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan PaymentSlow = TimeSpan.FromSeconds(120);

    private readonly AccountServices _services;
    private readonly Grid _page = new();
    private readonly DispatcherTimer _resendTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _paymentTimer = new() { Interval = PaymentPoll };
    private bool _quitting;
    private bool _busy;
    private string _email = "";
    private DateTimeOffset _resendAt;
    private TextBlock? _error;
    private Button? _resendButton;
    private TextBox[] _digits = [];
    private BillingPricing? _pricing;
    private BillingWallet? _wallet;
    private string _currency = "USD";

    // Pending journeys: a sign-in or credits request waiting for this window.
    private TaskCompletionSource<bool>? _signInWaiter;
    private TaskCompletionSource<bool>? _creditsWaiter;
    private (WidgetManifest Widget, WidgetTaskQuote Quote)? _creditsNeed;
    private bool _freeWidget;
    private (BillingOrder Order, DateTimeOffset StartedAt)? _payment;

    public AccountWindow(AccountServices services)
    {
        _services = services;
        Title = L.T("Glance Account");
        Width = SheetWidth;
        Height = SheetHeight;
        ResizeMode = ResizeMode.NoResize;
        Background = Ui.Brush("InspectInk1Brush");
        FontFamily = Ui.UiFont;
        UseLayoutRounding = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        ShowInTaskbar = true;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 44,
            ResizeBorderThickness = new Thickness(0),
            GlassFrameThickness = new Thickness(0, 0, 0, 1),
            UseAeroCaptionButtons = false,
        });
        var close = new Button
        {
            Content = new TextBlock { Text = Ui.GlyphChromeClose, FontFamily = Ui.IconFont, FontSize = 10 },
            ToolTip = L.T("Close"),
            Style = Ui.Style("CaptionCloseButton"),
            Height = 44,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
        };
        close.Click += (_, _) => Close();
        WindowChrome.SetIsHitTestVisibleInChrome(close, true);
        Content = new Border
        {
            BorderBrush = Ui.Brush("InspectLineBrush"),
            BorderThickness = new Thickness(1),
            Child = new Grid { Children = { _page, close } },
        };
        _resendTimer.Tick += (_, _) => UpdateResend();
        _paymentTimer.Tick += async (_, _) => await CheckPaymentAsync(automatic: true);
        services.Changed += (_, _) => OnAuthChanged();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                Close();
                e.Handled = true;
            }
        };
    }

    // ───────────────────────────── Public API ─────────────────────────────

    /// <summary>The wallet when signed in, otherwise sign-in.</summary>
    public void ShowAccount(Window? owner)
    {
        Present(owner);
        if (_services.Auth.IsSignedIn) _ = ShowWalletAsync();
        else ShowLogin(L.T("Sign in to Glance"), L.T("Sign in to keep your tasks and results together."));
    }

    /// <summary>
    /// macOS <c>requireWidgetSignIn</c>: true at once when signed in; otherwise shows sign-in and
    /// completes when the user signs in (true) or closes the window (false).
    /// </summary>
    public Task<bool> RequireSignInAsync(Window? owner, bool freeWidget)
    {
        if (_services.Auth.IsSignedIn) return Task.FromResult(true);
        _signInWaiter?.TrySetResult(false);
        _signInWaiter = new TaskCompletionSource<bool>();
        _freeWidget = freeWidget;
        Present(owner);
        _ = ShowWidgetLoginAsync();
        return _signInWaiter.Task;
    }

    /// <summary>
    /// The balance doesn't cover <paramref name="quote"/>: shows "%d more credits needed" and the
    /// packs. Completes true when the user submits after the credits arrive, false otherwise.
    /// </summary>
    public Task<bool> RequireCreditsAsync(Window? owner, WidgetManifest widget, WidgetTaskQuote quote)
    {
        _creditsWaiter?.TrySetResult(false);
        _creditsWaiter = new TaskCompletionSource<bool>();
        _creditsNeed = (widget, quote);
        Present(owner);
        _ = ShowTopUpAsync();
        return _creditsWaiter.Task;
    }

    /// <summary>A sign-in callback failed (e.g. expired state): show it on the login page.</summary>
    public void ShowAuthenticationError(string message)
    {
        Present(null);
        if (_error is null || _services.Auth.IsSignedIn)
            ShowLogin(L.T("Sign in to Glance"), L.T("Sign in to keep your tasks and results together."));
        SetError(L.T(message));
    }

    /// <summary><c>glance://payment/return?order=…</c>: only a hint to check the order now.</summary>
    public void HandlePaymentReturn(string orderId)
    {
        if (_payment is { } p && p.Order.Id == orderId) _ = CheckPaymentAsync(automatic: false);
    }

    public void Shutdown()
    {
        _quitting = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        base.OnClosing(e);
        if (e.Cancel) return;
        _resendTimer.Stop();
        _paymentTimer.Stop();
        _signInWaiter?.TrySetResult(_services.Auth.IsSignedIn);
        _signInWaiter = null;
        _creditsWaiter?.TrySetResult(false);
        _creditsWaiter = null;
        _creditsNeed = null;
        if (!_quitting)
        {
            e.Cancel = true;
            Hide();
        }
    }

    private void Present(Window? owner)
    {
        if (!IsVisible)
        {
            var monitor = ScreenGeometry.MonitorAtCursor();
            ScreenManager.Place(this, ScreenManager.CenterFrame(new Size(SheetWidth, SheetHeight), monitor));
            Show();
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    private void OnAuthChanged()
    {
        if (!_services.Auth.IsSignedIn) return;
        _resendTimer.Stop();
        if (_signInWaiter is { } waiter)
        {
            _signInWaiter = null;
            Log.Info("Account: sign-in completed for a waiting action");
            // Return to the action that asked (macOS waits one run-loop turn, then calls back).
            Hide();
            Dispatcher.BeginInvoke(new Action(() => waiter.TrySetResult(true)), DispatcherPriority.Background);
            return;
        }
        if (IsVisible && (_digits.Length > 0 || _error is not null) && _payment is null && _creditsNeed is null) _ = ShowWalletAsync();
    }

    // ───────────────────────────── Login ─────────────────────────────

    private async Task ShowWidgetLoginAsync()
    {
        ShowLogin(L.T("Sign in to use AI Widgets"), _freeWidget ? L.T("Sign in to keep your tasks and results together.") : L.F("New accounts receive %d credits.", _pricing?.SignupCredits ?? 100));
        if (_pricing is null && !_freeWidget)
        {
            await LoadPricingAsync();
            if (_digits.Length == 0 && _signInWaiter is not null && !_services.Auth.IsSignedIn)
                ShowLogin(L.T("Sign in to use AI Widgets"), L.F("New accounts receive %d credits.", _pricing?.SignupCredits ?? 100), keepEmail: true);
        }
    }

    private void ShowLogin(string title, string subtitle, bool keepEmail = false)
    {
        _digits = [];
        var column = Column(432);
        column.Children.Add(Heading(title));
        column.Children.Add(Subtitle(subtitle));
        var google = MakeButton(L.T("Continue with Google"), primary: false, StartGoogle);
        google.Margin = new Thickness(0, 28, 0, 0);
        column.Children.Add(google);
        column.Children.Add(Divider(L.T("Or use an email code")));
        column.Children.Add(FieldLabel(L.T("Email address")));
        var email = new TextBox { Style = Ui.Style("FieldBox"), Height = 44, Text = keepEmail ? _email : _email, Margin = new Thickness(0, 6, 0, 0) };
        email.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) _ = SendCodeAsync(email.Text);
        };
        column.Children.Add(email);
        var send = MakeButton(L.T("Send code"), primary: true, () => _ = SendCodeAsync(email.Text));
        send.Margin = new Thickness(0, 12, 0, 0);
        column.Children.Add(send);
        column.Children.Add(Note(L.T("Your image and Widget inputs are kept while you sign in.")));
        column.Children.Add(ErrorLine());
        column.Children.Add(Links());
        SetPage(column);
        Dispatcher.BeginInvoke(new Action(() => email.Focus()), DispatcherPriority.Input);
    }

    private void StartGoogle()
    {
        var url = _services.Auth.BeginGoogleSignIn();
        Log.Info("Account: opening Google sign-in in the browser");
        ShellActions.Open(url.AbsoluteUri);
        SetError(L.T("Continue in your browser to finish Google sign-in."), info: true);
        // The browser has to hand glance://auth/callback back to Glance. When it doesn't (the
        // "Open Glance?" prompt was dismissed, or the browser blocked it), say what to do instead of
        // waiting silently.
        var error = _error;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(45) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (_services.Auth.IsSignedIn || _error != error || !IsVisible) return;
            Log.Info("Account: no Google sign-in callback after 45 s");
            SetError(L.T("Still waiting for your browser. If it asked to open Glance, choose Open. If nothing happened, sign in with an email code below instead."), info: false);
        };
        timer.Start();
    }

    private async Task SendCodeAsync(string email)
    {
        if (_busy) return;
        email = email.Trim();
        if (!AuthService.IsValidEmail(email))
        {
            SetError(L.T("Enter a valid email address."));
            return;
        }
        _busy = true;
        SetError(L.T("Sending code..."), info: true);
        try
        {
            await _services.Auth.SendCodeAsync(email);
            _email = email;
            _resendAt = DateTimeOffset.UtcNow.AddSeconds(ResendSeconds);
            ShowCode();
        }
        catch (ApiException ex)
        {
            Log.Info($"Account: request failed: {ex.Code} (HTTP {(ex.Status is { } st ? (int)st : 0)}): {ex.Message}");
            SetError(L.T(ex.Message));
        }
        finally
        {
            _busy = false;
        }
    }

    private void ShowCode()
    {
        var column = Column(432);
        column.Children.Add(Heading(L.T("Enter your code")));
        column.Children.Add(Subtitle(L.F("Enter the six-digit code sent to %@. It expires in 10 minutes.", _email)));
        var cells = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 28, 0, 0) };
        _digits = new TextBox[6];
        for (var i = 0; i < 6; i++)
        {
            var index = i;
            var box = new TextBox
            {
                Style = Ui.Style("FieldBox"),
                Width = 62,
                Height = 52,
                FontFamily = Ui.CodeFont,
                FontSize = 20,
                MaxLength = 1,
                TextAlignment = TextAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center,
                Margin = new Thickness(i == 0 ? 0 : 12, 0, 0, 0),
            };
            box.PreviewTextInput += (_, e) => e.Handled = !e.Text.All(char.IsAsciiDigit);
            box.TextChanged += (_, _) =>
            {
                if (box.Text.Length == 1 && index < 5) _digits[index + 1].Focus();
                if (_digits.All(d => d.Text.Length == 1)) _ = VerifyAsync();
            };
            box.PreviewKeyDown += (_, e) =>
            {
                if (e.Key == Key.Back && box.Text.Length == 0 && index > 0)
                {
                    _digits[index - 1].Focus();
                    _digits[index - 1].Clear();
                    e.Handled = true;
                }
                else if (e.Key == Key.Enter)
                {
                    _ = VerifyAsync();
                    e.Handled = true;
                }
            };
            DataObject.AddPastingHandler(box, (_, e) =>
            {
                e.CancelCommand();
                if (e.DataObject.GetData(DataFormats.UnicodeText) is not string text) return;
                var digits = text.Where(char.IsAsciiDigit).Take(6 - index).ToArray();
                for (var k = 0; k < digits.Length; k++) _digits[index + k].Text = digits[k].ToString();
                _digits[Math.Min(5, index + digits.Length)].Focus();
            });
            _digits[i] = box;
            cells.Children.Add(box);
        }
        column.Children.Add(cells);
        var verify = MakeButton(L.T("Verify and sign in"), primary: true, () => _ = VerifyAsync());
        verify.Margin = new Thickness(0, 16, 0, 0);
        column.Children.Add(verify);
        _resendButton = MakeButton(L.T("Resend code"), primary: false, () => _ = ResendAsync());
        _resendButton.Margin = new Thickness(0, 12, 0, 0);
        column.Children.Add(_resendButton);
        var other = MakeButton(L.T("Use another email"), primary: false, () => ShowLogin(L.T("Sign in to Glance"), L.T("Sign in to keep your tasks and results together."), keepEmail: true));
        other.Style = Ui.Style("InspectTextButton");
        other.Margin = new Thickness(0, 12, 0, 0);
        column.Children.Add(other);
        column.Children.Add(ErrorLine());
        SetPage(column);
        UpdateResend();
        _resendTimer.Start();
        Dispatcher.BeginInvoke(new Action(() => _digits[0].Focus()), DispatcherPriority.Input);
    }

    private void UpdateResend()
    {
        if (_resendButton is null) return;
        var left = (int)Math.Ceiling((_resendAt - DateTimeOffset.UtcNow).TotalSeconds);
        _resendButton.IsEnabled = left <= 0 && !_busy;
        _resendButton.Content = left > 0 ? L.F("Resend in %d seconds", left) : L.T("Resend code");
        if (left <= 0) _resendTimer.Stop();
    }

    private async Task ResendAsync()
    {
        if (_busy) return;
        _busy = true;
        try
        {
            await _services.Auth.SendCodeAsync(_email);
            _resendAt = DateTimeOffset.UtcNow.AddSeconds(ResendSeconds);
            if (_digits.Length == 0) ShowCode();
            else _resendTimer.Start();
            SetError(L.T("Code sent. Check your email and enter the 6 digit code."), info: true);
        }
        catch (ApiException ex)
        {
            Log.Info($"Account: request failed: {ex.Code} (HTTP {(ex.Status is { } st ? (int)st : 0)}): {ex.Message}");
            SetError(L.T(ex.Message));
        }
        finally
        {
            _busy = false;
            UpdateResend();
        }
    }

    private async Task VerifyAsync()
    {
        if (_busy || _digits.Length != 6) return;
        var code = string.Concat(_digits.Select(d => d.Text));
        if (code.Length != 6 || !code.All(char.IsAsciiDigit))
        {
            SetError(L.T("Enter the six-digit code."));
            return;
        }
        _busy = true;
        SetError(L.T("Verifying code..."), info: true);
        try
        {
            await _services.Auth.VerifyCodeAsync(_email, code);
            // Success continues in OnAuthChanged.
        }
        catch (ApiException ex) when (ex.Code == "code_unavailable")
        {
            ShowStatus(L.T("Request a new code"), L.T("This code expired or has no attempts left.") + "\n\n" + L.T("One code per email every 60 seconds, up to 20 per network each hour."),
                L.T("Resend code"), () => _ = ResendAsync(), L.T("Use another email"), () => ShowLogin(L.T("Sign in to Glance"), L.T("Sign in to keep your tasks and results together."), keepEmail: true));
        }
        catch (ApiException ex)
        {
            SetError(ex.AttemptsRemaining is { } left ? L.F("Incorrect code. %d attempts left.", left) : L.T(ex.Message));
            foreach (var d in _digits) d.Clear();
            if (_digits.Length > 0) _digits[0].Focus();
        }
        finally
        {
            _busy = false;
        }
    }

    // ───────────────────────────── Wallet ─────────────────────────────

    private async Task ShowWalletAsync()
    {
        RenderWallet();
        try
        {
            _wallet = await _services.Billing.FetchWalletAsync();
            if (_payment is null && _creditsNeed is null && _services.Auth.IsSignedIn && IsVisible) RenderWallet();
        }
        catch (ApiException ex)
        {
            Log.Info($"Account: wallet unavailable: {ex.Message}");
            if (_payment is null && _creditsNeed is null && IsVisible)
            {
                RenderWallet();
                SetError(L.T(ex.Message));
            }
        }
    }

    private void RenderWallet()
    {
        if (!_services.Auth.IsSignedIn || _services.Auth.Session is not { } session)
        {
            ShowLogin(L.T("Sign in to Glance"), L.T("Sign in to keep your tasks and results together."));
            return;
        }
        _digits = [];
        var column = Column(512);
        column.Children.Add(new TextBlock { Text = L.T("CREDITS WALLET"), FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush") });
        var balance = _wallet?.Balance ?? session.User.Credits ?? 0;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        row.Children.Add(new TextBlock { Text = balance.ToString("N0", CultureInfo.CurrentCulture), FontSize = 56, Foreground = Ui.Brush(balance < 0 ? "FailureBrush" : "InspectText1Brush") });
        row.Children.Add(new TextBlock { Text = L.T("credits"), FontSize = 14, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(10, 0, 0, 14) });
        column.Children.Add(row);
        column.Children.Add(Subtitle(session.User.Email));
        var topUp = MakeButton(L.T("Top up credits"), primary: true, () => _ = ShowTopUpAsync());
        topUp.Margin = new Thickness(0, 16, 0, 0);
        topUp.HorizontalAlignment = HorizontalAlignment.Left;
        column.Children.Add(topUp);
        column.Children.Add(Note(balance < 0
            ? L.T("Paid Widgets are paused until the negative balance is cleared.")
            : L.T("No expiry. Only cloud Widgets use credits. Local tools do not.")));

        var list = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        var transactions = _wallet?.Transactions ?? [];
        if (_wallet is not null && transactions.Count == 0) list.Children.Add(Note(L.T("No transactions yet.")));
        foreach (var t in transactions.Take(50)) list.Children.Add(TransactionRow(t));
        column.Children.Add(new ScrollViewer { Content = list, MaxHeight = 200, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        column.Children.Add(ErrorLine());

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) };
        var signOut = MakeButton(L.T("Sign out"), primary: false, ConfirmSignOut);
        signOut.Style = Ui.Style("InspectTextButton");
        footer.Children.Add(signOut);
        column.Children.Add(footer);
        SetPage(column);
    }

    private static UIElement TransactionRow(BillingTransaction t)
    {
        var grid = new Grid { Height = 39 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var date = new TextBlock { Text = t.CreatedAt?.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "", FontFamily = Ui.CodeFont, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center };
        var label = new TextBlock { Text = TransactionLabel(t), FontSize = 13, Foreground = Ui.Brush("InspectText1Brush"), VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        var amount = new TextBlock
        {
            Text = t.Amount > 0 ? $"+{t.Amount}" : t.Amount.ToString(CultureInfo.InvariantCulture),
            FontFamily = Ui.CodeFont,
            FontSize = 12,
            Foreground = Ui.Brush(t.Amount > 0 ? "SuccessBrush" : "InspectText2Brush"),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(label, 1);
        Grid.SetColumn(amount, 2);
        grid.Children.Add(date);
        grid.Children.Add(label);
        grid.Children.Add(amount);
        return new Border { BorderBrush = Ui.Brush("InspectLineBrush"), BorderThickness = new Thickness(0, 0, 0, 1), Child = grid };
    }

    /// <summary>macOS transaction labels by reason.</summary>
    private static string TransactionLabel(BillingTransaction t) => t.Reason switch
    {
        "signup" or "signup_bonus" => L.T("New account gift"),
        "purchase_credits" => L.T("Credit top-up"),
        "pro_bonus" => L.T("Pro purchase gift"),
        "widget_task" => t.WidgetName ?? L.T("Widget task"),
        "task_refund" => L.F("%@ refunded", t.WidgetName ?? L.T("Widget task")),
        "order_refund" => L.T("Order refund recovery"),
        "admin_adjust" => t.Note ?? L.T("Balance adjustment"),
        _ => t.Note ?? t.Reason,
    };

    private void ConfirmSignOut() =>
        ShowStatus(L.T("Sign out?"), L.T("Pending task submissions will be cleared. Files and account credits are kept."),
            L.T("Sign out"), () =>
            {
                _services.Auth.SignOut();
                _wallet = null;
                ShowLogin(L.T("Sign in to Glance"), L.T("Sign in to keep your tasks and results together."));
            },
            L.T("Cancel"), RenderWallet);

    // ───────────────────────────── Top-up & payment ─────────────────────────────

    private async Task LoadPricingAsync()
    {
        if (_pricing is not null) return;
        try
        {
            _pricing = await _services.Billing.FetchPricingAsync();
            _currency = _pricing.DefaultCurrency;
        }
        catch (ApiException ex)
        {
            Log.Info($"Account: pricing unavailable: {ex.Message}");
        }
    }

    private async Task ShowTopUpAsync()
    {
        if (!_services.Auth.IsSignedIn)
        {
            if (!await RequireSignInAsync(this, freeWidget: false)) return;
            Present(null);
        }
        SetPage(Loading());
        await LoadPricingAsync();
        try
        {
            _wallet = await _services.Billing.FetchWalletAsync();
        }
        catch (ApiException)
        {
        }
        RenderTopUp();
    }

    private void RenderTopUp()
    {
        _digits = [];
        var column = Column(432);
        var balance = _wallet?.Balance ?? _services.Credits ?? 0;
        if (_creditsNeed is { } need)
        {
            var name = need.Widget.DisplayName(_services.Language);
            var cost = need.Quote.TotalCredits;
            if (balance >= cost)
            {
                RenderReadyToSubmit(balance, cost);
                return;
            }
            column.Children.Add(Heading(L.F("%d more credits needed", cost - balance)));
            column.Children.Add(Subtitle(L.F("%@ costs %d credits. Current balance: %d. Nothing has been charged.", name, cost, balance)));
        }
        else
        {
            column.Children.Add(Heading(L.T("Top up credits")));
            column.Children.Add(Subtitle(L.T("Top up as needed. No subscription or expiry.")));
        }

        if (_pricing is null || _pricing.Packs.Count == 0)
        {
            column.Children.Add(ErrorLine());
            SetPage(column);
            SetError(_pricing is null ? L.T("Could not complete this action") : L.T("No credit packages are available yet."));
            return;
        }
        if (!_pricing.PaymentsAvailable && !_pricing.MockCheckout)
        {
            column.Children.Add(ErrorLine());
            SetPage(column);
            SetError(L.T("Payments are not available yet. Contact support for credits."));
            return;
        }

        var currencies = _pricing.Packs.SelectMany(p => p.Prices.Keys).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(c => c, StringComparer.Ordinal).ToList();
        if (!currencies.Contains(_currency, StringComparer.OrdinalIgnoreCase)) _currency = currencies.FirstOrDefault() ?? "USD";
        var packs = _pricing.Packs.Where(p => p.PriceIn(_currency) is not null).ToList();
        var selected = packs.FirstOrDefault(p => p.Recommended) ?? packs.FirstOrDefault();
        var list = new StackPanel { Margin = new Thickness(0, 24, 0, 0) };
        var radios = new List<RadioButton>();
        foreach (var pack in packs)
        {
            var price = pack.PriceIn(_currency)!;
            var credits = pack.Credits + pack.BonusCredits;
            var content = new Grid { Width = 380 };
            content.Children.Add(new TextBlock { Text = L.F("%d credits", credits), FontSize = 13, Foreground = Ui.Brush("InspectText1Brush") });
            content.Children.Add(new TextBlock { Text = BillingClient.FormatPrice(price, _currency), FontFamily = Ui.CodeFont, FontSize = 12, Foreground = Ui.Brush("InspectText2Brush"), HorizontalAlignment = HorizontalAlignment.Right });
            var radio = new RadioButton { Content = content, GroupName = "packs", IsChecked = pack == selected, Height = 44, VerticalContentAlignment = VerticalAlignment.Center, Tag = pack, Margin = new Thickness(0, 0, 0, 8) };
            radios.Add(radio);
            list.Children.Add(new Border { BorderBrush = Ui.Brush("InspectLineBrush"), BorderThickness = new Thickness(1), CornerRadius = Ui.Corner("CornerControl"), Padding = new Thickness(12, 0, 12, 0), Margin = new Thickness(0, 0, 0, 8), Child = radio });
        }
        column.Children.Add(list);

        if (currencies.Count > 1)
        {
            var picker = new ComboBox { ItemsSource = currencies, SelectedItem = currencies.First(c => c.Equals(_currency, StringComparison.OrdinalIgnoreCase)), Width = 120, HorizontalAlignment = HorizontalAlignment.Left };
            picker.SelectionChanged += (_, _) =>
            {
                if (picker.SelectedItem is string currency && currency != _currency)
                {
                    _currency = currency;
                    RenderTopUp();
                }
            };
            var currencyRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
            currencyRow.Children.Add(new TextBlock { Text = L.T("Pay with"), FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) });
            currencyRow.Children.Add(picker);
            column.Children.Add(currencyRow);
        }
        if (_pricing.MockCheckout) column.Children.Add(Note(L.T("Simulated payment for testing. No money is charged.")));

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 20, 0, 0) };
        var pay = MakeButton(L.T("Continue to payment"), primary: true, () =>
        {
            if (radios.FirstOrDefault(r => r.IsChecked == true)?.Tag is BillingPack pack) _ = StartPaymentAsync(pack);
        });
        buttons.Children.Add(pay);
        var notNow = MakeButton(L.T("Not now"), primary: false, () =>
        {
            if (_creditsWaiter is not null) Close();
            else _ = ShowWalletAsync();
        });
        notNow.Margin = new Thickness(10, 0, 0, 0);
        buttons.Children.Add(notNow);
        column.Children.Add(buttons);
        column.Children.Add(ErrorLine());
        SetPage(column);
    }

    private void RenderReadyToSubmit(int balance, int cost)
    {
        var column = Column(432);
        column.Children.Add(Heading(L.T("Ready to submit")));
        column.Children.Add(Row(L.T("Current balance"), L.F("%d credits", balance)));
        column.Children.Add(Row(L.T("This task"), L.F("%d credits", cost)));
        var submit = MakeButton(L.F("Submit for %d credits", cost), primary: true, () =>
        {
            var waiter = _creditsWaiter;
            _creditsWaiter = null;
            _creditsNeed = null;
            Hide();
            waiter?.TrySetResult(true);
        });
        submit.Margin = new Thickness(0, 24, 0, 0);
        submit.HorizontalAlignment = HorizontalAlignment.Left;
        column.Children.Add(submit);
        SetPage(column);
    }

    private async Task StartPaymentAsync(BillingPack pack)
    {
        if (_busy) return;
        _busy = true;
        SetError(L.T("Preparing…"), info: true);
        try
        {
            var checkout = await _services.Billing.CreateCreditsOrderAsync(pack, _currency, _services.Language, intentId: null);
            if (checkout.CheckoutUrl is { } url)
            {
                ShellActions.Open(url);
                Log.Info("Account: opened checkout in the browser");
            }
            _payment = (checkout.Order, DateTimeOffset.UtcNow);
            RenderPayment(checkout, slow: false);
            _paymentTimer.Start();
        }
        catch (ApiException ex)
        {
            Log.Info($"Account: request failed: {ex.Code} (HTTP {(ex.Status is { } st ? (int)st : 0)}): {ex.Message}");
            SetError(L.T(ex.Message));
        }
        finally
        {
            _busy = false;
        }
    }

    private void RenderPayment(BillingCheckout? checkout, bool slow)
    {
        if (_payment is not { } payment) return;
        var order = payment.Order;
        var column = Column(432);
        column.Children.Add(Heading(slow ? L.T("Payment confirmation is taking longer") : L.T("Complete payment in your browser")));
        column.Children.Add(Row(L.T("Order"), order.Id));
        column.Children.Add(Row(L.T("Amount"), BillingClient.FormatPrice(new BillingPrice(order.Amount, null), order.Currency)));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 24, 0, 0) };
        buttons.Children.Add(MakeButton(slow ? L.T("Check again") : L.T("I have completed payment"), primary: true, () => _ = CheckPaymentAsync(automatic: false)));
        if (slow && _pricing?.SupportEmail is { } support)
        {
            var contact = MakeButton(L.T("Contact support"), primary: false, () => ShellActions.Open($"mailto:{support}?subject={Uri.EscapeDataString("Glance payment " + order.Id)}"));
            contact.Margin = new Thickness(10, 0, 0, 0);
            buttons.Children.Add(contact);
        }
        else
        {
            var abandon = MakeButton(L.T("Abandon payment"), primary: false, () => _ = AbandonPaymentAsync());
            abandon.Margin = new Thickness(10, 0, 0, 0);
            buttons.Children.Add(abandon);
        }
        column.Children.Add(buttons);
        column.Children.Add(ErrorLine());
        SetPage(column);
    }

    private async Task CheckPaymentAsync(bool automatic)
    {
        if (_payment is not { } payment) return;
        try
        {
            var (order, balance) = await _services.Billing.FetchOrderAsync(payment.Order.Id);
            if (_payment?.Order.Id != order.Id) return;
            if (order.IsPaid)
            {
                _paymentTimer.Stop();
                _payment = null;
                Log.Info("Account: payment confirmed");
                _wallet = await _services.Billing.FetchWalletAsync();
                if (_creditsNeed is { } need) RenderReadyToSubmit(_wallet.Balance, need.Quote.TotalCredits);
                else RenderWallet();
                return;
            }
            if (order.Status is "expired" or "refunded")
            {
                _paymentTimer.Stop();
                _payment = null;
                ShowStatus(L.T("Order expired"), L.T("Nothing has been charged."), L.T("Top up credits"), () => _ = ShowTopUpAsync(), L.T("Done"), Close);
                return;
            }
            var slow = DateTimeOffset.UtcNow - payment.StartedAt > PaymentSlow;
            if (slow && automatic)
            {
                _paymentTimer.Stop();
                RenderPayment(null, slow: true);
            }
            else if (!automatic)
            {
                RenderPayment(null, slow);
                SetError(L.T("Payment not confirmed yet. If you paid, wait a moment and check again."), info: true);
            }
        }
        catch (ApiException ex)
        {
            if (!automatic) SetError(L.T(ex.Message));
        }
    }

    private async Task AbandonPaymentAsync()
    {
        if (_payment is not { } payment) return;
        _paymentTimer.Stop();
        _payment = null;
        try
        {
            await _services.Billing.AbandonOrderAsync(payment.Order.Id);
        }
        catch (ApiException ex)
        {
            Log.Info($"Account: abandon order failed: {ex.Message}");
        }
        RenderTopUp();
    }

    // ───────────────────────────── Status page ─────────────────────────────

    private void ShowStatus(string title, string body, string primary, Action primaryAction, string? secondary = null, Action? secondaryAction = null)
    {
        _digits = [];
        var column = Column(432);
        column.Children.Add(Heading(title));
        column.Children.Add(Subtitle(body));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 24, 0, 0) };
        buttons.Children.Add(MakeButton(primary, primary: true, primaryAction));
        if (secondary is not null && secondaryAction is not null)
        {
            var second = MakeButton(secondary, primary: false, secondaryAction);
            second.Margin = new Thickness(10, 0, 0, 0);
            buttons.Children.Add(second);
        }
        column.Children.Add(buttons);
        column.Children.Add(ErrorLine());
        SetPage(column);
    }

    // ───────────────────────────── Builders ─────────────────────────────

    private void SetPage(UIElement content)
    {
        _page.Children.Clear();
        _page.Children.Add(content);
    }

    private StackPanel Column(double width)
    {
        _error = null;
        _resendButton = null;
        return new StackPanel { Width = width, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 84, 0, 0) };
    }

    private static UIElement Loading() => new TextBlock
    {
        Text = L.T("Loading…"),
        FontSize = 13,
        Foreground = Ui.Brush("InspectText3Brush"),
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private static TextBlock Heading(string text) => new()
    {
        Text = text,
        FontSize = 24,
        Foreground = Ui.Brush("InspectText1Brush"),
        TextWrapping = TextWrapping.Wrap,
    };

    private static TextBlock Subtitle(string text) => new()
    {
        Text = text,
        FontSize = 13,
        Foreground = Ui.Brush("InspectText2Brush"),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 8, 0, 0),
    };

    private static TextBlock FieldLabel(string text) => new()
    {
        Text = text,
        FontSize = 12,
        FontWeight = FontWeights.Medium,
        Foreground = Ui.Brush("InspectText2Brush"),
        Margin = new Thickness(0, 4, 0, 0),
    };

    private static TextBlock Note(string text) => new()
    {
        Text = text,
        FontSize = 12,
        Foreground = Ui.Brush("InspectText3Brush"),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 14, 0, 0),
    };

    private TextBlock ErrorLine()
    {
        _error = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), Visibility = Visibility.Collapsed };
        return _error;
    }

    private void SetError(string message, bool info = false)
    {
        if (_error is null) return;
        _error.Text = message;
        _error.Foreground = Ui.Brush(info ? "InspectText3Brush" : "FailureBrush");
        _error.Visibility = string.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
    }

    private static UIElement Divider(string text)
    {
        var grid = new Grid { Margin = new Thickness(0, 16, 0, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var left = new Border { Height = 1, Background = Ui.Brush("InspectLineBrush"), VerticalAlignment = VerticalAlignment.Center };
        var label = new TextBlock { Text = text, FontSize = 11, Foreground = Ui.Brush("InspectText3Brush"), Margin = new Thickness(10, 0, 10, 0) };
        var right = new Border { Height = 1, Background = Ui.Brush("InspectLineBrush"), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(label, 1);
        Grid.SetColumn(right, 2);
        grid.Children.Add(left);
        grid.Children.Add(label);
        grid.Children.Add(right);
        return grid;
    }

    private static UIElement Row(string key, string value)
    {
        var grid = new Grid { Height = 36 };
        grid.Children.Add(new TextBlock { Text = key, FontSize = 12, Foreground = Ui.Brush("InspectText3Brush"), VerticalAlignment = VerticalAlignment.Center });
        grid.Children.Add(new TextBlock { Text = value, FontFamily = Ui.CodeFont, FontSize = 12, Foreground = Ui.Brush("InspectText1Brush"), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center });
        return new Border { BorderBrush = Ui.Brush("InspectLineBrush"), BorderThickness = new Thickness(0, 0, 0, 1), Child = grid };
    }

    private UIElement Links()
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 28, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
        if (_pricing?.TermsUrl is { } terms) panel.Children.Add(Link(L.T("Terms of service"), terms));
        if (_pricing?.PrivacyUrl is { } privacy)
        {
            var link = Link(L.T("Privacy policy"), privacy);
            link.Margin = new Thickness(16, 0, 0, 0);
            panel.Children.Add(link);
        }
        return panel;
    }

    private static Button Link(string text, string url)
    {
        var button = new Button { Content = text, Style = Ui.Style("InspectTextButton"), FontSize = 11 };
        button.Click += (_, _) => ShellActions.Open(url);
        return button;
    }

    private static Button MakeButton(string text, bool primary, Action onClick)
    {
        var button = new Button
        {
            Content = text,
            Style = Ui.Style(primary ? "InspectPrimaryButton" : "InspectQuietButton"),
            Height = 36,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        button.Click += (_, _) => onClick();
        return button;
    }
}
