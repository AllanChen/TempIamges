#!/usr/bin/env python3
"""Build the Glance website into ./public for Cloudflare Pages.

Pages live in src/pages/*.html. Each starts with a metadata comment:
  <!-- path: /pricing/ | zh: 价格 | en: Pricing | nav: pricing -->
The builder wraps every page with the shared header, footer and head tags,
copies src/assets, and writes Pages control files.
"""
from __future__ import annotations

import json
import re
import shutil
from html import escape
from pathlib import Path
from localize import localize

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "public"
SITE = "https://glancepreview.com"
# The former address and www redirect to SITE in functions/_middleware.js.
# Support is by direct message on X; there is no support mailbox.
SUPPORT_X_URL = "https://x.com/Sir03834855"
SUPPORT_X_HANDLE = "@Sir03834855"
SUPPORT_X = f'<a href="{SUPPORT_X_URL}" target="_blank" rel="noopener">{SUPPORT_X_HANDLE}</a>'
VERSION = "1.0.0-beta.1"
DMG = f"/download/Glance-{VERSION}.dmg"
# A pre-release version keeps beta positioning; a final version must ship a notarized DMG.
PRERELEASE = "-" in VERSION
UPDATED = "2026-11-05"

SNAPSHOT = json.loads((SRC / "public-snapshot.json").read_text(encoding="utf-8"))
PRICING_FALLBACK = SNAPSHOT["pricing"]

# The homepage is also published in Japanese and German. Their links to other
# pages go to the English versions.
HOME_EXTRA = ("ja", "de")
HTML_LANG = {"zh": "zh-CN", "en": "en", "ja": "ja", "de": "de"}
OG_LOCALE = {"zh": "zh_CN", "en": "en_US", "ja": "ja_JP", "de": "de_DE"}
HREFLANG = {"zh": "zh-Hans", "en": "en", "ja": "ja", "de": "de"}
LANGUAGE_NAME = {"zh": "中文", "en": "English", "ja": "日本語", "de": "Deutsch"}
HOME_META = {
    "ja": ("Glance — AI ツールと画像比較を備えた Mac 用画像・動画ビューア",
           "Glance は Mac 用の画像・動画ビューアです。画像を並べて比較し、画像内の文字を認識し、その場で AI ツールを使えます。Apple シリコン搭載 Mac 向けに無料でダウンロードできます。"),
    "de": ("Glance — Bild- und Videobetrachter für den Mac mit KI-Werkzeugen und Bildvergleich",
           "Glance ist ein Bild- und Videobetrachter für den Mac: Bilder nebeneinander vergleichen, Text in Bildern erkennen und KI-Werkzeuge direkt nutzen. Kostenloser Download für Macs mit Apple Silicon."),
}


def prefix(lang: str) -> str:
    return "" if lang == "zh" else "/" + lang


def page_languages(path: str, page_paths: set[str]) -> tuple[str, ...]:
    if path not in page_paths:
        return ("zh",)
    return ("zh", "en") + (HOME_EXTRA if path == "/" else ())


NAV = [
    ("features", "/#loop", "功能", "Features", "機能", "Funktionen"),
    ("widgets", "/widgets/", "AI Widget", "AI Widgets", "AI Widget", "KI-Widgets"),
    ("pricing", "/pricing/", "价格", "Pricing", "料金", "Preise"),
    ("install", "/install/", "安装", "Install", "インストール", "Installation"),
]

DESCRIPTIONS = {
    '/': ('Glance 是 Mac 图片和视频查看器，支持并排对比、图片文字识别和就地 AI 工具。免费下载 Apple 芯片 Mac '
          + ('内测版。' if PRERELEASE else '版。'),
          'View images and videos on your Mac, compare changes side by side, and run AI tools where you work. Download '
          + ('the Glance beta' if PRERELEASE else 'Glance') + ' for Apple silicon.'),
    '/pricing/': ('了解 Glance 免费查看、Pro 一次买断和云端 AI Widget 按次消耗点数的价格与功能。',
                 'Compare Glance Free and Pro, one-time Mac licenses, and credits for cloud AI Widgets. See what is included before you download.'),
    '/widgets/': ('查看 Glance AI Widget 的功能、每次点数价格、处理模型与媒体上传说明。',
                 'Explore Glance AI Widgets for your images and videos, including upscaling and background removal. See per-run credits and processing details.'),
    '/ai-models/': ('公开了解 Glance 各 AI Widget 的底层模型、版本信息、第三方处理服务和功能范围，无需登录。',
                    'Public disclosure of the AI models, version information, processing services and capabilities behind Glance Widgets. No login required.'),
    '/install/': ('下载 Glance macOS ' + ('内测版' if PRERELEASE else '版') + '，查看系统要求、安装步骤、首次启动说明和文件校验值。',
                 'Download Glance for Apple silicon Macs. Find system requirements, ' + ('beta ' if PRERELEASE else '')
                 + 'installation instructions, first-launch help, and the download checksum.'),
    '/terms/': ('阅读 Glance 的服务条款、账户与许可、云端任务和付款规则。',
               'Read the Glance terms of service for the Mac app, accounts, licenses, cloud tasks, and payments.'),
    '/privacy/': ('了解 Glance 的本地处理、云端 Widget 媒体上传和账户数据隐私政策。',
                 'Learn how Glance handles local processing, media uploaded for cloud Widgets, and account data in its privacy policy.'),
    '/refunds/': ('阅读 Glance Pro 和点数充值包退款政策，以及云端任务失败的退点说明。',
                 'Read the refund policy for Glance Pro and credit packs, and how refunds work when cloud Widget tasks fail.'),
    '/acceptable-use/': ('阅读 Glance AI Widget 的可接受使用政策、素材授权要求和违规内容举报方式。',
                        'Read the acceptable use policy for Glance AI Widgets, media permissions, and how to report prohibited content.'),
    '/compare-images-mac/': ('在 Mac 上用 Glance 并排或滑杆对比两张图片，检查原图和处理结果的细节。',
                            'Compare two images on Mac with Glance side by side or with a reveal slider. Inspect the original and result before using it.'),
    '/copy-text-from-image-mac/': ('在 Mac 上从图片选取并复制文字。了解系统自带方法和 Glance 的本地文字识别步骤及限制。',
                                  'Copy text from an image on Mac with built-in Live Text or Glance. Follow the local OCR steps and learn what affects recognition.'),
}

PAGE_TITLES = {
    '/compare-images-mac/': ('Mac 上对比两张图片：并排与滑杆检查 · Glance',
                            'Compare Two Images on Mac, Side by Side — Glance'),
    '/copy-text-from-image-mac/': ('Mac 图片文字识别与复制教程 · Glance',
                                  'Copy Text from an Image on Mac — Glance Guide'),
}


def widget_cards(lang: str, limit: int = 0) -> str:
    cards = []
    for widget in SNAPSHOT["widgets"][:limit or None]:
        # Japanese and German pages use the English catalog text with localized labels.
        name = widget["name"] if lang == "zh" else widget["enName"]
        summary = widget["summary"] if lang == "zh" else widget["enSummary"]
        cost = widget["creditCost"]
        billing = widget.get("billing") or {}
        if cost == 0:
            price = {"zh": "免费", "en": "Free", "ja": "無料", "de": "Kostenlos"}[lang]
        elif billing.get("mode") == "duration" and billing.get("unitSeconds"):
            seconds = billing["unitSeconds"]
            price = {"zh": f"{cost} 点 / {seconds} 秒", "en": f"{cost} credits / {seconds} sec",
                     "ja": f"{cost} クレジット / {seconds} 秒", "de": f"{cost} Credits / {seconds} s"}[lang]
        else:
            price = {"zh": f"{cost} 点 / 次", "en": f"{cost} credits / run",
                     "ja": f"{cost} クレジット / 回", "de": f"{cost} Credits / Ausführung"}[lang]
        privacy = ({"zh": "运行时上传所选媒体到云端处理", "en": "Uploads selected media for cloud processing",
                    "ja": "実行時に選択したメディアをクラウドにアップロードして処理", "de": "Lädt die ausgewählten Medien zur Verarbeitung in die Cloud hoch"}
                   if widget["uploadsMedia"] else
                   {"zh": "在 Glance 服务端处理", "en": "Processed by Glance servers",
                    "ja": "Glance のサーバーで処理", "de": "Wird auf Glance-Servern verarbeitet"})[lang]
        cards.append(f'<article class="widget"><div class="widget-icon" aria-hidden="true">{escape(name[:1])}</div>'
                     f'<div class="widget-body"><div class="widget-top"><h3>{escape(name)}</h3><span class="price">{escape(price)}</span></div>'
                     f'<p>{escape(summary)}</p><div class="meta">{escape(privacy)}</div></div></article>')
    return "".join(cards)


def pricing_cards(lang: str, kind: str) -> str:
    pricing = PRICING_FALLBACK
    available = pricing.get("enabled") and pricing.get("paymentsAvailable")
    if not available:
        message = (("In-app purchases are not open during this beta." if PRERELEASE else "In-app purchases are not open yet.")
                   if lang == "en" else ("内测期间应用内购买尚未开放。" if PRERELEASE else "应用内购买暂未开放。"))
        return f'<p class="notice">{message}</p>'
    currency = "USD" if lang == "en" else "CNY"
    rows = []
    items = pricing.get("proTiers" if kind == "tiers" else "packs") or []
    for item in items:
        amount = (item.get(currency) or {}).get("amount")
        if not item.get("enabled") or amount is None:
            continue
        money = ("$" if currency == "USD" else "¥") + f"{amount / 100:g}"
        if kind == "tiers":
            name = item["name"] if lang == "en" else {"Personal": "个人版", "Duo": "双机版", "Team (5 people)": "多人版"}.get(item["name"], item["name"])
            macs = ('5 people · 1 Mac each' if lang=='en' else '5 人 · 每人 1 台 Mac') if item['id']=='team' else (f'{item["deviceLimit"]} Macs' if lang == "en" else f'{item["deviceLimit"]} 台 Mac')
            rows.append(f'<div class="tier"><div class="tier-head"><b>{escape(name)}</b><span class="tier-macs">{macs}</span></div><div class="tier-price">{money}</div></div>')
        else:
            points = (item.get(currency) or {}).get("points", 0)
            unit = "credits" if lang == "en" else "点"
            rows.append(f'<div class="pack"><b>{points}</b><span>{unit} · {money}</span></div>')
    return "".join(rows) or ('<p class="notice">Prices are not published yet.</p>' if lang == 'en' else '<p class="notice">价格尚未公布。</p>')


def bi(zh: str, en: str, tag: str = "span", ja: str | None = None, de: str | None = None) -> str:
    """Shared chrome text. Japanese and German fall back to English when not given."""
    return "".join(f'<{tag} lang="{lang}">{text}</{tag}>'
                   for lang, text in (("zh", zh), ("en", en), ("ja", ja or en), ("de", de or en)))


def header(active: str, lang: str, options: list[tuple[str, str]]) -> str:
    links = "".join(
        f'<a class="hide-sm" href="{href}"{" aria-current=\"page\"" if key == active else ""}>{bi(zh, en, ja=ja, de=de)}</a>'
        for key, href, zh, en, ja, de in NAV)
    # A <details> menu needs no script; site.js only closes it on outside click or Escape.
    items = "".join(f'<a class="lang-option" href="{href}" hreflang="{HREFLANG[option]}"'
                    f'{" aria-current=\"true\"" if option == lang else ""}>{LANGUAGE_NAME[option]}</a>'
                    for option, href in options)
    toggles = (f'<details class="lang-menu"><summary class="lang-toggle" aria-label="Language">{LANGUAGE_NAME[lang]}</summary>'
               f'<div class="lang-menu-list">{items}</div></details>')
    return f"""<a class="skip" href="#main">{bi("跳到正文", "Skip to content", ja="本文へ移動", de="Zum Inhalt springen")}</a>
<header class="site-header"><div class="wrap">
  <a class="brand" href="/"><img src="/assets/img/logo-256.png" alt="" width="30" height="30">Glance</a>
  <nav class="nav" aria-label="Main">{links}
    {toggles}
    <a class="btn btn-primary" href="/#download">{bi("下载", "Download", ja="ダウンロード")}</a>
  </nav>
</div></header>"""


def footer() -> str:
    legal = lambda zh, en, ja, de: bi(zh, en, ja=ja + "（英語）", de=de + " (Englisch)")
    return f"""<footer class="site-footer"><div class="wrap">
  <div class="footer-grid">
    <div>
      <a class="brand" href="/" style="display:flex;padding:0;color:var(--text)"><img src="/assets/img/logo-256.png" alt="" width="30" height="30">Glance</a>
      <p style="margin:14px 0 0;max-width:320px">{bi("AI 时代的 Preview。看图看视频，不满意就地用 AI 改，改完对比确认。",
        "The Preview for the AI era. View images and video, fix them in place with AI, then compare to confirm.",
        ja="AI 時代の Preview。画像や動画を開き、その場で AI で直して、比較して確かめる。",
        de="Die Vorschau für das KI-Zeitalter: Bilder und Videos ansehen, direkt mit KI überarbeiten und vergleichen.")}</p>
    </div>
    <div><h4>{bi("产品", "Product", ja="製品", de="Produkt")}</h4>
      <a href="/#loop">{bi("功能", "Features", ja="機能", de="Funktionen")}</a><a href="/widgets/">{bi("AI Widget", "AI Widgets", ja="AI Widget（英語）", de="KI-Widgets (Englisch)")}</a>
      <a href="/ai-models/">{legal("AI 模型说明", "AI Model Disclosure", "AI モデルの開示", "Offenlegung der KI-Modelle")}</a>
      <a href="/pricing/">{legal("价格", "Pricing", "料金", "Preise")}</a><a href="/install/">{legal("下载与安装", "Download & install", "ダウンロードとインストール", "Download &amp; Installation")}</a></div>
    <div><h4>{bi("使用指南", "Guides", ja="ガイド", de="Anleitungen")}</h4>
      <a href="/compare-images-mac/">{legal("对比两张图片", "Compare two images", "2 枚の画像を比較", "Zwei Bilder vergleichen")}</a>
      <a href="/copy-text-from-image-mac/">{legal("从图片复制文字", "Copy text from an image", "画像から文字をコピー", "Text aus einem Bild kopieren")}</a></div>
    <div><h4>{bi("政策", "Legal", ja="規約とポリシー", de="Rechtliches")}</h4>
      <a href="/terms/">{legal("服务条款", "Terms of Service", "利用規約", "Nutzungsbedingungen")}</a><a href="/privacy/">{legal("隐私政策", "Privacy Policy", "プライバシーポリシー", "Datenschutzerklärung")}</a>
      <a href="/refunds/">{legal("退款政策", "Refund Policy", "返金ポリシー", "Rückerstattungsrichtlinie")}</a><a href="/acceptable-use/">{legal("可接受使用政策", "Acceptable Use Policy", "利用ポリシー", "Nutzungsrichtlinie")}</a></div>
    <div><h4>{bi("支持", "Support", ja="サポート", de="Support")}</h4>
      <a href="{SUPPORT_X_URL}" target="_blank" rel="noopener">{bi("X 私信 " + SUPPORT_X_HANDLE, "DM " + SUPPORT_X_HANDLE + " on X",
        ja="X で DM：" + SUPPORT_X_HANDLE, de="DM auf X: " + SUPPORT_X_HANDLE)}</a>
      <a href="/acceptable-use/#report">{legal("举报违规内容", "Report content", "違反コンテンツを報告", "Inhalte melden")}</a></div>
  </div>
  <div class="footer-bottom">
    <span>© 2026 Glance · glancepreview.com</span>
    <span>{bi("付款由 Pancake by Waffo 作为记录商户（Merchant of Record）处理。",
      "Payments are processed by Pancake by Waffo as Merchant of Record.",
      ja="お支払いは Pancake by Waffo が販売事業者（Merchant of Record）として処理します。",
      de="Zahlungen wickelt Pancake by Waffo als Merchant of Record ab.")}</span>
  </div>
</div></footer>"""


def homepage_schema(lang: str, description: str) -> str:
    data = {
        "@context": "https://schema.org",
        "@graph": [
            {"@type": "Organization", "@id": SITE + "/#organization", "name": "Glance",
             "url": SITE + "/", "logo": SITE + "/assets/img/logo-256.png", "sameAs": [SUPPORT_X_URL]},
            {"@type": "WebSite", "@id": SITE + "/#website", "name": "Glance",
             "url": SITE + "/", "inLanguage": ["zh-CN", "en", "ja", "de"],
             "publisher": {"@id": SITE + "/#organization"}},
            {"@type": "SoftwareApplication", "@id": SITE + "/#app", "name": "Glance",
             "url": SITE + prefix(lang) + "/",
             "description": description, "applicationCategory": "MultimediaApplication",
             "operatingSystem": "macOS 12.3 or later, Apple silicon",
             "softwareVersion": VERSION, "downloadUrl": SITE + DMG,
             "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"}},
        ],
    }
    return '<script type="application/ld+json">' + json.dumps(data, ensure_ascii=False).replace('<', '\\u003c') + '</script>'


def page(meta: dict, body: str, lang: str, page_paths: set[str]) -> str:
    base_path = meta['path']
    path = prefix(lang) + base_path
    if lang in HOME_META:
        title, desc = HOME_META[lang]
    else:
        title = f'{meta[lang]} · Glance'
        if base_path == '/':
            title = 'Glance — Mac Image Viewer with AI Tools & Comparison' if lang == 'en' else 'Glance — Mac 图片与视频查看器、AI 工具和图片对比'
        elif base_path in PAGE_TITLES:
            title = PAGE_TITLES[base_path][lang == 'en']
        desc = DESCRIPTIONS.get(base_path, (meta['zh'] + ' · Glance', meta['en'] + ' · Glance'))[lang == 'en']
    schema = homepage_schema(lang, desc) if base_path == '/' else ''
    title, desc = escape(title, quote=True), escape(desc, quote=True)
    canonical = SITE + path
    languages = page_languages(base_path, page_paths)
    alternatives = ''
    if base_path in page_paths:
        options = [(other, prefix(other) + base_path) for other in languages]
        alternatives = '\n'.join(f'<link rel="alternate" hreflang="{HREFLANG[other]}" href="{SITE}{prefix(other)}{base_path}">'
                                 for other in languages)
        alternatives += f'\n<link rel="alternate" hreflang="x-default" href="{SITE}/en{base_path}">'
    else:
        options = [('zh', base_path), ('en', '/en/')]
    robots = '<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    # Pancake by Waffo store verification; checked on the homepage only.
    verify = '<meta name="waffo-verify" content="26c71f44eeec84b752100c39e4b32fc3">' if meta["path"] == "/" else ""
    return f"""<!doctype html>
<html lang="{HTML_LANG[lang]}" data-lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{canonical}">
{alternatives}
<meta property="og:title" content="{title}">
<meta property="og:description" content="{desc}">
<meta property="og:type" content="website">
<meta property="og:locale" content="{OG_LOCALE[lang]}">
<meta property="og:image" content="{SITE}/assets/video/glance-demo-poster{'' if lang == 'zh' else '-en'}.jpg">
<meta property="og:url" content="{canonical}">
<meta name="twitter:card" content="summary_large_image">
{schema}
<meta name="theme-color" content="#08090c">
{robots}
{verify}
<link rel="icon" type="image/png" href="/assets/img/favicon-64.png">
<link rel="apple-touch-icon" href="/assets/img/logo-256.png">
<link rel="stylesheet" href="/assets/site.css?v={ASSET_VERSION}">
</head>
<body>
{localize(header(meta.get('nav', ''), lang, options), lang, page_paths)}
<main id="main">
{localize(body, lang, page_paths)}
</main>
{localize(footer(), lang, page_paths)}
<script src="/assets/site.js?v={ASSET_VERSION}" defer></script>
</body>
</html>
"""


def render(text: str, lang: str) -> str:
    replacements = {
        "{{SUPPORT_X}}": SUPPORT_X, "{{VERSION}}": VERSION, "{{DMG}}": DMG,
        "{{UPDATED}}": UPDATED, "{{SITE}}": SITE,
        "{{PRICING_JSON}}": json.dumps(PRICING_FALLBACK, ensure_ascii=False).replace('<', '\\u003c'),
        "{{PRICING_TIERS}}": pricing_cards(lang, "tiers"),
        "{{PRICING_PACKS}}": pricing_cards(lang, "packs"),
        "{{WIDGET_CARDS_ALL}}": widget_cards(lang),
        "{{WIDGET_CARDS_HOME}}": widget_cards(lang, 6),
        "{{DMG_SIZE}}": DMG_SIZE, "{{DMG_SHA256}}": DMG_SHA256,
    }
    for key, value in replacements.items():
        text = text.replace(key, value)
    leftover = re.findall(r"\{\{[A-Z0-9_]+\}\}", text)
    if leftover:
        raise SystemExit(f"Unresolved placeholders: {leftover}")
    return text


def asset_version() -> str:
    """Content hash of the shared CSS and JS, so every change gets a new URL
    and no browser or edge cache can serve a stale script."""
    import hashlib
    digest = hashlib.sha256()
    for name in ("site.css", "site.js"):
        digest.update((SRC / "assets" / name).read_bytes())
    return digest.hexdigest()[:10]


ASSET_VERSION = asset_version()


def dmg_facts() -> tuple[str, str]:
    import hashlib
    path = SRC / DMG.lstrip("/")
    if not path.exists():
        raise SystemExit(f"Missing download: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return f"{path.stat().st_size / 1_000_000:.1f} MB", digest


DMG_SIZE, DMG_SHA256 = dmg_facts()


def dmg_notarized() -> bool:
    """True only when the published DMG carries a stapled ticket that Gatekeeper accepts."""
    import subprocess
    path = str(SRC / DMG.lstrip("/"))
    checks = (["xcrun", "stapler", "validate", path],
              ["spctl", "-a", "-t", "open", "--context", "context:primary-signature", path])
    try:
        return all(subprocess.run(c, capture_output=True, timeout=60).returncode == 0 for c in checks)
    except (OSError, subprocess.TimeoutExpired):
        return False


NOTARIZED = dmg_notarized()
if not PRERELEASE and not NOTARIZED:
    raise SystemExit(f"Release {VERSION} requires a notarized, stapled DMG: {DMG}")
SALES_OPEN = bool(PRICING_FALLBACK.get("enabled") and PRICING_FALLBACK.get("paymentsAvailable"))
FLAGS = {"beta": PRERELEASE, "notarized": NOTARIZED, "sales": SALES_OPEN}


def conditional(text: str) -> str:
    """Resolve <!--if:flag-->…<!--endif--> and <!--if:!flag-->…<!--endif--> (innermost first)
    so release-dependent copy always matches the DMG and sales state being published."""
    def choose(match: re.Match) -> str:
        negate, flag, content = match.groups()
        if flag not in FLAGS:
            raise SystemExit(f"Unknown build flag: {flag}")
        return content if FLAGS[flag] != bool(negate) else ""
    pattern = re.compile(r"<!--if:(!?)([a-z]+)-->((?:(?!<!--if:).)*?)<!--endif-->", re.S)
    while True:
        text, count = pattern.subn(choose, text)
        if not count:
            break
    if "<!--if:" in text or "<!--endif-->" in text:
        raise SystemExit("Unbalanced build conditional")
    return text


def load_pages(folder: Path) -> list[tuple[dict, str]]:
    pages = []
    seen = {}
    for source in sorted(folder.glob('*.html')):
        raw = source.read_text(encoding="utf-8")
        match = re.match(r"<!--(.*?)-->\s*", raw, re.S)
        if not match:
            raise SystemExit(f"{source.name}: missing metadata comment")
        meta = dict(part.split(":", 1) for part in (p.strip() for p in match.group(1).split("|")) if part)
        meta = {k.strip(): v.strip() for k, v in meta.items()}
        if "noindex" in meta:
            meta["noindex"] = meta["noindex"] == "true"
        path = meta['path']
        if path in seen:
            raise ValueError(f'Duplicate page path {path}: {seen[path]} and {source.name}')
        seen[path] = source.name
        pages.append((meta, conditional(raw[match.end():])))
    return pages


def main() -> None:
    pages = load_pages(SRC / 'pages')
    page_paths = {meta['path'] for meta, _ in pages if not meta.get('noindex')}
    # Validate and render everything before replacing the generated output.
    rendered = []
    for meta, body in pages:
        for lang in page_languages(meta['path'], page_paths):
            path = prefix(lang) + meta['path']
            rendered.append((path, meta.get('noindex'), render(page(meta, body, lang, page_paths), lang)))
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SRC / 'assets', OUT / 'assets')
    shutil.copytree(SRC / 'download', OUT / 'download')
    shutil.copytree(SRC / 'updates', OUT / 'updates')
    paths = []
    for path, noindex, html in rendered:
        if path == '/404':
            target = OUT / "404.html"
        else:
            target = OUT / path.strip('/') / 'index.html'
            if not noindex:
                paths.append(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(html, encoding="utf-8")
    (OUT / "_headers").write_text(f"""/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  X-Frame-Options: DENY
  Permissions-Policy: camera=(), microphone=(), geolocation=()
/assets/*
  Cache-Control: public, max-age=86400
/download/*
  Cache-Control: public, max-age=3600
  Content-Disposition: attachment
/updates/appcast.xml
  Cache-Control: no-cache
/pay/*
  Cache-Control: no-store
  X-Robots-Tag: noindex
""", encoding="utf-8")
    (OUT / "_redirects").write_text(f"""/refund /refunds/ 301
/refund/ /refunds/ 301
/Glance-1.0.0.dmg {DMG} 302
/download {DMG} 302
/download/ {DMG} 302
/aup /acceptable-use/ 301
""", encoding="utf-8")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /pay/return/\nDisallow: /pay/\nAllow: /\nSitemap: {SITE}/sitemap.xml\n", encoding="utf-8")
    # Omit optional lastmod until per-page content dates are maintained.
    urls = "".join(f"<url><loc>{SITE}{p}</loc></url>" for p in paths)
    (OUT / "sitemap.xml").write_text(
        f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>\n',
        encoding="utf-8")
    print(f"Built {len(list(OUT.rglob('index.html')))} pages into {OUT}")


if __name__ == "__main__":
    main()
