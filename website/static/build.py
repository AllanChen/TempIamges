#!/usr/bin/env python3
"""Build the Glance website into ./public for Cloudflare Pages.

Pages live in src/pages/*.html. Each starts with a metadata comment:
  <!-- path: /pricing/ | zh: 价格 | en: Pricing | nav: pricing -->
The builder wraps every page with the shared header, footer and head tags,
copies src/assets, and writes Pages control files.
"""
from __future__ import annotations

import json
import sys
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
UPDATED = "2026-11-05"
# IndexNow ownership key. It is public by design: the deploy script pings
# api.indexnow.org with changed URLs, and engines verify it at /<key>.txt.
INDEXNOW_KEY = "909a04701230a0b72c22faa5c10d16e1"

SNAPSHOT = json.loads((SRC / "public-snapshot.json").read_text(encoding="utf-8"))
PRICING_FALLBACK = SNAPSHOT["pricing"]

# zh (root) and en (/en/) come from bilingual sources with inline lang
# attributes. Every extra language is a full translation file per page under
# src/i18n/<code>/, and only translated pages are built for it.
LANGUAGES = {
    # code: (url prefix, <html lang>, hreflang, og:locale)
    'zh': ('', 'zh-CN', 'zh-Hans', 'zh_CN'),
    'en': ('/en', 'en', 'en', 'en_US'),
    'ja': ('/ja', 'ja', 'ja', 'ja_JP'),
    'de': ('/de', 'de', 'de', 'de_DE'),
}
LANGUAGE_NAMES = {'zh': '中文', 'en': 'English', 'ja': '日本語', 'de': 'Deutsch'}
EXTRA_LANGUAGES = [code for code in LANGUAGES if code not in ('zh', 'en')]


def url_for(lang: str, base_path: str) -> str:
    return LANGUAGES[lang][0] + base_path


NAV = [
    ("features", "/#loop", "功能", "Features"),
    ("widgets", "/widgets/", "AI Widget", "AI Widgets"),
    ("pricing", "/pricing/", "价格", "Pricing"),
    ("install", "/install/", "安装", "Install"),
]

DESCRIPTIONS = {
    '/': ('Glance 是 Mac 图片和视频查看器，支持并排对比、图片文字识别和就地 AI 工具。免费下载 Apple 芯片 Mac 内测版。',
          'View images and videos on your Mac, compare changes side by side, and run AI tools where you work. Download the Glance beta for Apple silicon.'),
    '/pricing/': ('了解 Glance 免费查看、Pro 一次买断和云端 AI Widget 按次消耗点数的价格与功能。',
                 'Compare Glance Free and Pro, one-time Mac licenses, and credits for cloud AI Widgets. See what is included before you download.'),
    '/widgets/': ('查看 Glance AI Widget 的功能、每次点数价格、处理模型与媒体上传说明。',
                 'Explore Glance AI Widgets for your images and videos, including upscaling and background removal. See per-run credits and processing details.'),
    '/ai-models/': ('公开了解 Glance 各 AI Widget 的底层模型、版本信息、第三方处理服务和功能范围，无需登录。',
                    'Public disclosure of the AI models, version information, processing services and capabilities behind Glance Widgets. No login required.'),
    '/install/': ('下载 Glance macOS 内测版，查看系统要求、安装步骤、首次启动说明和文件校验值。',
                 'Download Glance for Apple silicon Macs. Find system requirements, beta installation instructions, first-launch help, and the download checksum.'),
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


# Widget summaries for extra languages; names stay in English as shown in the
# app, which ships only English and Simplified Chinese UI.
WIDGET_SUMMARIES = {'ja': {
    "Video Watermark Remover": "10 秒ごとに 100 クレジット（端数切り上げ）。区間ごとに処理して 1 本の動画にまとめます。",
    "Upscale": "画像を高解像度化し、ディテールをくっきりさせます。",
    "Background Remover Pro": "髪の毛などの細かい輪郭を残したまま、背景を精密に削除します。",
    "Free Image Host": "画像や動画をアップロードして共有リンクを取得します。",
    "Image to Prompt": "画像の内容を、プロンプトとして再利用できる文章にします。",
    "Watermark Remover": "画像の透かし、文字、マークを除去します。",
    "Expand Image": "画像の外側を、元画像になじむ内容で広げます。",
    "Outfit Swap": "1 枚目の人物に、2 枚目の服を着せ替えます。",
    "Redraw & Reframe": "指定したアスペクト比で画像を描き直します。",
}, 'de': {
    "Video Watermark Remover": "100 Credits pro angefangene 10 Sekunden. Bereinigt Abschnitte und fügt sie wieder zu einem Video zusammen.",
    "Upscale": "Skaliert Bilder auf eine höhere Auflösung mit schärferen Details hoch.",
    "Background Remover Pro": "Präzise Hintergrundentfernung, die feine Kanten wie Haare erhält.",
    "Free Image Host": "Bild oder Video hochladen und einen Link zum Teilen erhalten.",
    "Image to Prompt": "Beschreibt ein Bild in Worten, die Sie als Prompt wiederverwenden können.",
    "Watermark Remover": "Entfernt Wasserzeichen, Text und Markierungen aus einem Bild.",
    "Expand Image": "Erweitert die Leinwand über die Bildränder hinaus mit passendem Inhalt.",
    "Outfit Swap": "Kleidet die Person im ersten Bild mit dem Outfit aus dem zweiten Bild ein.",
    "Redraw & Reframe": "Erzeugt das Bild im gewählten Seitenverhältnis neu.",
}}


def widget_cards(lang: str, limit: int = 0) -> str:
    cards = []
    zh = lang == "zh"
    for widget in SNAPSHOT["widgets"][:limit or None]:
        name = widget["name"] if zh else widget["enName"]
        summary = widget["summary"] if zh else widget["enSummary"]
        if lang in WIDGET_SUMMARIES:
            summary = WIDGET_SUMMARIES[lang].get(widget["enName"], summary)
        cost = widget["creditCost"]
        billing = widget.get("billing") or {}
        words = {"zh": ("免费", "{c} 点 / {s} 秒", "{c} 点 / 次", "运行时上传所选媒体到云端处理", "在 Glance 服务端处理"),
                 "en": ("Free", "{c} credits / {s} sec", "{c} credits / run", "Uploads selected media for cloud processing", "Processed by Glance servers"),
                 "ja": ("無料", "{s} 秒ごとに {c} クレジット", "1 回 {c} クレジット", "実行時に選択したメディアをクラウドへアップロード", "Glance のサーバーで処理"),
                 "de": ("Kostenlos", "{c} Credits / {s} Sek.", "{c} Credits / Lauf", "Lädt die gewählten Medien zur Cloud-Verarbeitung hoch", "Verarbeitung auf Glance-Servern")}[lang]
        if cost == 0:
            price = words[0]
        elif billing.get("mode") == "duration" and billing.get("unitSeconds"):
            price = words[1].format(c=cost, s=billing["unitSeconds"])
        else:
            price = words[2].format(c=cost)
        privacy = words[3] if widget["uploadsMedia"] else words[4]
        cards.append(f'<article class="widget"><div class="widget-icon" aria-hidden="true">{escape(name[:1])}</div>'
                     f'<div class="widget-body"><div class="widget-top"><h3>{escape(name)}</h3><span class="price">{escape(price)}</span></div>'
                     f'<p>{escape(summary)}</p><div class="meta">{escape(privacy)}</div></div></article>')
    return "".join(cards)


def pricing_cards(lang: str, kind: str) -> str:
    pricing = PRICING_FALLBACK
    available = pricing.get("enabled") and pricing.get("paymentsAvailable")
    if not available:
        message = {"en": "In-app purchases are not open during this beta.", "ja": "ベータ期間中はアプリ内購入をまだ受け付けていません。", "de": "In-App-Käufe sind während der Beta noch nicht möglich."}.get(lang, "内测期间应用内购买尚未开放。")
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


# Shared header/footer text for extra languages, keyed by the English string.
CHROME = {
    'ja': {"Features": "機能", "AI Widgets": "AI ウィジェット", "Pricing": "料金", "Install": "インストール",
           "Skip to content": "本文へスキップ", "Download": "ダウンロード", "Product": "製品",
           "AI Model Disclosure": "AI モデルの開示", "Download & install": "ダウンロードとインストール",
           "Guides": "ガイド", "Compare two images": "2 枚の画像を比較", "Copy text from an image": "画像から文字をコピー",
           "Legal": "規約（英語）", "Terms of Service": "利用規約", "Privacy Policy": "プライバシーポリシー",
           "Refund Policy": "返金ポリシー", "Acceptable Use Policy": "利用ポリシー", "Support": "サポート",
           "Report content": "違反コンテンツの報告", "Use cases": "使い方", "Blog": "ブログ",
           "The Preview for the AI era. View images and video, fix them in place with AI, then compare to confirm.":
               "AI 時代のプレビュー。画像や動画をすばやく見て、気になれば AI でその場で直し、比較して確認。",
           "Payments are processed by Pancake by Waffo as Merchant of Record.":
               "決済は Pancake by Waffo が販売事業者（Merchant of Record）として処理します。"},
    'de': {"Features": "Funktionen", "AI Widgets": "KI-Widgets", "Pricing": "Preise", "Install": "Installieren",
           "Skip to content": "Zum Inhalt springen", "Download": "Download", "Product": "Produkt",
           "AI Model Disclosure": "KI-Modelle offengelegt", "Download & install": "Download & Installation",
           "Guides": "Anleitungen", "Compare two images": "Zwei Bilder vergleichen", "Copy text from an image": "Text aus Bild kopieren",
           "Legal": "Rechtliches (Englisch)", "Terms of Service": "Nutzungsbedingungen", "Privacy Policy": "Datenschutz",
           "Refund Policy": "Rückerstattung", "Acceptable Use Policy": "Nutzungsrichtlinie", "Support": "Support",
           "Report content": "Inhalte melden", "Use cases": "Anwendungsfälle", "Blog": "Blog",
           "The Preview for the AI era. View images and video, fix them in place with AI, then compare to confirm.":
               "Die Vorschau fürs KI-Zeitalter. Bilder und Videos ansehen, direkt mit KI korrigieren und dann vergleichen.",
           "Payments are processed by Pancake by Waffo as Merchant of Record.":
               "Zahlungen wickelt Pancake by Waffo als Merchant of Record ab."},
}


def bi(zh: str, en: str, tag: str = "span") -> str:
    """Shared chrome text in every language; extra languages fall back to English."""
    extra = ''.join(f'<{tag} lang="{code}">{CHROME[code].get(en, en)}</{tag}>' for code in EXTRA_LANGUAGES)
    return f'<{tag} lang="zh">{zh}</{tag}><{tag} lang="en">{en}</{tag}>' + extra


def header(active: str, alternate: str, others: list[tuple[str, str]] = ()) -> str:
    links = "".join(
        f'<a class="hide-sm" href="{href}"{" aria-current=\"page\"" if key == active else ""}>{bi(zh, en)}</a>'
        for key, href, zh, en in NAV)
    return f"""<a class="skip" href="#main">{bi("跳到正文", "Skip to content")}</a>
<header class="site-header"><div class="wrap">
  <a class="brand" href="/"><img src="/assets/img/logo-256.png" alt="" width="30" height="30">Glance</a>
  <nav class="nav" aria-label="Main">{links}
    <a class="lang-toggle" href="{alternate}" aria-label="Switch language"><span lang="zh">EN</span><span lang="en">中文</span>{''.join(f'<span lang="{c}">English</span>' for c in EXTRA_LANGUAGES)}</a>{''.join(f'<a class="lang-toggle hide-sm" href="{href}" hreflang="{code}">{LANGUAGE_NAMES[code]}</a>' for code, href in others)}
    <a class="btn btn-primary" href="/#download">{bi("下载", "Download")}</a>
  </nav>
</div></header>"""


def footer() -> str:
    return f"""<footer class="site-footer"><div class="wrap">
  <div class="footer-grid">
    <div>
      <a class="brand" href="/" style="display:flex;padding:0;color:var(--text)"><img src="/assets/img/logo-256.png" alt="" width="30" height="30">Glance</a>
      <p style="margin:14px 0 0;max-width:320px">{bi("AI 时代的 Preview。看图看视频，不满意就地用 AI 改，改完对比确认。",
        "The Preview for the AI era. View images and video, fix them in place with AI, then compare to confirm.")}</p>
    </div>
    <div><h4>{bi("产品", "Product")}</h4>
      <a href="/#loop">{bi("功能", "Features")}</a><a href="/widgets/">{bi("AI Widget", "AI Widgets")}</a>
      <a href="/ai-models/">{bi("AI 模型说明", "AI Model Disclosure")}</a>
      <a href="/pricing/">{bi("价格", "Pricing")}</a><a href="/install/">{bi("下载与安装", "Download & install")}</a></div>
    <div><h4>{bi("使用指南", "Guides")}</h4>
      <a href="/compare-images-mac/">{bi("对比两张图片", "Compare two images")}</a>
      <a href="/copy-text-from-image-mac/">{bi("从图片复制文字", "Copy text from an image")}</a>
      <a lang="en" href="/en/use-cases/">Use cases</a><a lang="en" href="/en/blog/">Blog</a>{''.join(f'<a lang="{c}" href="/{c}/use-cases/">{CHROME[c]["Use cases"]}</a><a lang="{c}" href="/{c}/blog/">{CHROME[c]["Blog"]}</a>' for c in EXTRA_LANGUAGES)}</div>
    <div><h4>{bi("政策", "Legal")}</h4>
      <a href="/terms/">{bi("服务条款", "Terms of Service")}</a><a href="/privacy/">{bi("隐私政策", "Privacy Policy")}</a>
      <a href="/refunds/">{bi("退款政策", "Refund Policy")}</a><a href="/acceptable-use/">{bi("可接受使用政策", "Acceptable Use Policy")}</a></div>
    <div><h4>{bi("支持", "Support")}</h4>
      <a href="{SUPPORT_X_URL}" target="_blank" rel="noopener">{bi("X 私信 @Sir03834855", "DM @Sir03834855 on X")}</a>
      <a href="/acceptable-use/#report">{bi("举报违规内容", "Report content")}</a></div>
  </div>
  <div class="footer-bottom">
    <span>© 2026 Glance · glancepreview.com</span>
    <span>{bi("付款由 Pancake by Waffo 作为记录商户（Merchant of Record）处理。",
      "Payments are processed by Pancake by Waffo as Merchant of Record.")}</span>
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
             "url": SITE + url_for(lang, "/"),
             "description": description, "applicationCategory": "MultimediaApplication",
             "operatingSystem": "macOS 12.3 or later, Apple silicon",
             "softwareVersion": VERSION, "downloadUrl": SITE + DMG,
             "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"}},
        ],
    }
    return '<script type="application/ld+json">' + json.dumps(data, ensure_ascii=False).replace('<', '\\u003c') + '</script>'


def page(meta: dict, body: str, lang: str, page_paths: set[str]) -> str:
    base_path = meta['path']
    path = url_for(lang, base_path)
    title = f'{meta.get(lang, meta['en'])} · Glance'
    if base_path == '/':
        title = 'Glance — Mac Image Viewer with AI Tools & Comparison' if lang == 'en' else 'Glance — Mac 图片与视频查看器、AI 工具和图片对比'
    elif base_path in PAGE_TITLES:
        title = PAGE_TITLES[base_path][lang == 'en']
    desc = DESCRIPTIONS.get(base_path, (meta['zh'] + ' · Glance', meta['en'] + ' · Glance'))[lang == 'en']
    translated = None
    if lang in EXTRA_LANGUAGES:
        # Extra languages: the whole body, title and description come from
        # src/i18n/<lang>/; links to untranslated pages fall back to /en/.
        tmeta, body = TRANSLATIONS[lang][base_path]
        title, desc = tmeta['title'], tmeta['desc']
        translated = set(TRANSLATIONS[lang])
    schema = homepage_schema(lang, desc) if base_path == '/' else ''
    title, desc = escape(title, quote=True), escape(desc, quote=True)
    canonical = SITE + path
    alternate = '/en' + base_path if lang == 'zh' else base_path if lang == 'en' else '/en' + base_path
    alternatives = ''
    if base_path in page_paths:
        alternatives = hreflang_links(base_path)
    else:
        alternate = '/en/'
    robots = '<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    # Pancake by Waffo store verification; checked on the homepage only.
    verify = '<meta name="waffo-verify" content="26c71f44eeec84b752100c39e4b32fc3">' if meta["path"] == "/" else ""
    return f"""<!doctype html>
<html lang="{LANGUAGES[lang][1]}" data-lang="{lang}">
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
<meta property="og:locale" content="{LANGUAGES[lang][3]}">
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
{localize(header(meta.get('nav', ''), alternate, language_links(lang, base_path) if base_path in page_paths else ()), lang, page_paths, translated)}
<main id="main">
{localize(body, lang, page_paths, translated)}
</main>
{localize(footer(), lang, page_paths, translated)}
<script src="/assets/site.js?v={ASSET_VERSION}" defer></script>
</body>
</html>
"""


def load_translations() -> dict[str, dict[str, tuple[dict, str]]]:
    """src/i18n/<code>/*.html: one fully translated page body per file, with a
    metadata comment `path | title | desc | nav`. Paths must exist in src/pages."""
    result = {}
    for code in EXTRA_LANGUAGES:
        folder = SRC / 'i18n' / code
        result[code] = {meta['path']: (meta, body) for meta, body in (load_pages(folder) if folder.is_dir() else [])}
    return result


def languages_for(base_path: str) -> list[str]:
    return ['zh', 'en'] + [code for code in EXTRA_LANGUAGES if base_path in TRANSLATIONS[code]]


def language_links(lang: str, base_path: str) -> list[tuple[str, str]]:
    """Extra-language links next to the zh/en toggle: every other version of
    this page in the extra languages, plus zh from an extra-language page."""
    return [(code, url_for(code, base_path)) for code in languages_for(base_path)
            if code != lang and code in EXTRA_LANGUAGES or (lang in EXTRA_LANGUAGES and code == 'zh')]


def hreflang_links(base_path: str) -> str:
    links = [f'<link rel="alternate" hreflang="{LANGUAGES[code][2]}" href="{SITE}{url_for(code, base_path)}">'
             for code in languages_for(base_path)]
    links.append(f'<link rel="alternate" hreflang="x-default" href="{SITE}/en{base_path}">')
    return '\n'.join(links)



def render(text: str, lang: str) -> str:
    replacements = {
        "{{SUPPORT_X}}": SUPPORT_X, "{{SUPPORT_X_URL}}": SUPPORT_X_URL, "{{SUPPORT_X_HANDLE}}": SUPPORT_X_HANDLE,
        "{{VERSION}}": VERSION, "{{DMG}}": DMG,
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
        pages.append((meta, raw[match.end():]))
    return pages


TRANSLATIONS = load_translations()


def main() -> None:
    for code, pages_ in TRANSLATIONS.items():
        unknown = set(pages_) - {meta['path'] for meta, _ in load_pages(SRC / 'pages')}
        if unknown:
            raise ValueError(f'{code} translations for unknown pages: {sorted(unknown)}')
    pages = load_pages(SRC / 'pages')
    page_paths = {meta['path'] for meta, _ in pages if not meta.get('noindex')}
    # Validate and render everything before replacing the generated output.
    rendered = []
    for meta, body in pages:
        for lang in (languages_for(meta['path']) if meta['path'] in page_paths else ('zh',)):
            path = url_for(lang, meta['path'])
            rendered.append((path, meta.get('noindex'), render(page(meta, body, lang, page_paths), lang)))
    from content import render_content
    rendered.extend(render_content(sys.modules[__name__], page_paths))
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
    (OUT / f"{INDEXNOW_KEY}.txt").write_text(INDEXNOW_KEY, encoding="utf-8")
    # Omit optional lastmod until per-page content dates are maintained.
    urls = "".join(f"<url><loc>{SITE}{p}</loc></url>" for p in paths)
    (OUT / "sitemap.xml").write_text(
        f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>\n',
        encoding="utf-8")
    print(f"Built {len(list(OUT.rglob('index.html')))} pages into {OUT}")


if __name__ == "__main__":
    main()
