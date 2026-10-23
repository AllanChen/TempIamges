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
SUPPORT_EMAIL = "support@mcreator.ai"
VERSION = "1.0.0-beta.1"
DMG = f"/download/Glance-{VERSION}.dmg"
UPDATED = "2026-10-16"

# Last published pricing. The live page replaces it with /api/v2/pricing,
# which is edited in Admin. Amounts are minor units (fen / cents).
PRICING_FALLBACK = {
    "trialDays": 14, "signupCredits": 100, "proBonusCredits": 100, "deviceLimit": 2,
    "offlineDays": 30, "launchUntil": None,
    "proTiers": [
        {"id": "personal", "name": "Personal", "enabled": True, "recommended": False, "deviceLimit": 1,
         "CNY": {"amount": 9800}, "USD": {"amount": 1490}, "launchCNY": {"amount": 6800}, "launchUSD": {"amount": 990}},
        {"id": "duo", "name": "Duo", "enabled": True, "recommended": True, "deviceLimit": 2,
         "CNY": {"amount": 13800}, "USD": {"amount": 1990}, "launchCNY": {"amount": 9800}, "launchUSD": {"amount": 1490}},
    ],
    "packs": [
        {"id": "small", "enabled": True, "recommended": False,
         "CNY": {"amount": 1200, "points": 120}, "USD": {"amount": 299, "points": 120}},
        {"id": "standard", "enabled": True, "recommended": True,
         "CNY": {"amount": 3000, "points": 330}, "USD": {"amount": 499, "points": 330}},
        {"id": "large", "enabled": True, "recommended": False,
         "CNY": {"amount": 9800, "points": 1200}, "USD": {"amount": 1499, "points": 1200}},
    ],
}

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
}


def bi(zh: str, en: str, tag: str = "span") -> str:
    return f'<{tag} lang="zh">{zh}</{tag}><{tag} lang="en">{en}</{tag}>'


def header(active: str, alternate: str) -> str:
    links = "".join(
        f'<a class="hide-sm" href="{href}"{" aria-current=\"page\"" if key == active else ""}>{bi(zh, en)}</a>'
        for key, href, zh, en in NAV)
    return f"""<a class="skip" href="#main">{bi("跳到正文", "Skip to content")}</a>
<header class="site-header"><div class="wrap">
  <a class="brand" href="/"><img src="/assets/img/logo-256.png" alt="" width="30" height="30">Glance</a>
  <nav class="nav" aria-label="Main">{links}
    <a class="lang-toggle" href="{alternate}" aria-label="Switch language">{bi("EN", "中文")}</a>
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
    <div><h4>{bi("政策", "Legal")}</h4>
      <a href="/terms/">{bi("服务条款", "Terms of Service")}</a><a href="/privacy/">{bi("隐私政策", "Privacy Policy")}</a>
      <a href="/refunds/">{bi("退款政策", "Refund Policy")}</a><a href="/acceptable-use/">{bi("可接受使用政策", "Acceptable Use Policy")}</a></div>
    <div><h4>{bi("支持", "Support")}</h4>
      <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>
      <a href="/acceptable-use/#report">{bi("举报违规内容", "Report content")}</a></div>
  </div>
  <div class="footer-bottom">
    <span>© 2026 Glance · mcreator.ai</span>
    <span>{bi("付款由 Pancake by Waffo 作为记录商户（Merchant of Record）处理。",
      "Payments are processed by Pancake by Waffo as Merchant of Record.")}</span>
  </div>
</div></footer>"""


def page(meta: dict, body: str, lang: str, page_paths: set[str]) -> str:
    base_path = meta['path']
    path = '/en' + base_path if lang == 'en' else base_path
    title = f'{meta[lang]} · Glance'
    if base_path == '/':
        title = 'Glance — Mac Image Viewer with AI Tools & Comparison' if lang == 'en' else 'Glance — Mac 图片与视频查看器、AI 工具和图片对比'
    desc = DESCRIPTIONS.get(base_path, (meta['zh'] + ' · Glance', meta['en'] + ' · Glance'))[lang == 'en']
    title, desc = escape(title, quote=True), escape(desc, quote=True)
    canonical = SITE + path
    alternate = base_path if lang == 'en' else '/en' + base_path
    alternatives = ''
    if base_path in page_paths:
        alternatives = f'''<link rel="alternate" hreflang="zh-Hans" href="{SITE}{base_path}">
<link rel="alternate" hreflang="en" href="{SITE}/en{base_path}">
<link rel="alternate" hreflang="x-default" href="{SITE}/en{base_path}">'''
    else:
        alternate = '/en/'
    robots = '<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    # Pancake by Waffo store verification; checked on the homepage only.
    verify = '<meta name="waffo-verify" content="26c71f44eeec84b752100c39e4b32fc3">' if meta["path"] == "/" else ""
    return f"""<!doctype html>
<html lang="{'en' if lang == 'en' else 'zh-CN'}" data-lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{canonical}">
{alternatives}
<meta property="og:title" content="{title}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="{SITE}/assets/video/glance-demo-poster{'-en' if lang == 'en' else ''}.jpg">
<meta property="og:url" content="{canonical}">
<meta name="theme-color" content="#08090c">
{robots}
{verify}
<link rel="icon" type="image/png" href="/assets/img/favicon-64.png">
<link rel="apple-touch-icon" href="/assets/img/logo-256.png">
<link rel="stylesheet" href="/assets/site.css?v={ASSET_VERSION}">
</head>
<body>
{localize(header(meta.get('nav', ''), alternate), lang, page_paths)}
<main id="main">
{localize(body, lang, page_paths)}
</main>
{localize(footer(), lang, page_paths)}
<script src="/assets/site.js?v={ASSET_VERSION}" defer></script>
</body>
</html>
"""


def render(text: str) -> str:
    replacements = {
        "{{SUPPORT_EMAIL}}": SUPPORT_EMAIL, "{{VERSION}}": VERSION, "{{DMG}}": DMG,
        "{{UPDATED}}": UPDATED, "{{SITE}}": SITE,
        "{{PRICING_JSON}}": json.dumps(PRICING_FALLBACK, ensure_ascii=False),
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


def main() -> None:
    pages = load_pages(SRC / 'pages')
    page_paths = {meta['path'] for meta, _ in pages if not meta.get('noindex')}
    # Validate and render everything before replacing the generated output.
    rendered = []
    for meta, body in pages:
        for lang in (('zh', 'en') if meta['path'] in page_paths else ('zh',)):
            path = '/en' + meta['path'] if lang == 'en' else meta['path']
            rendered.append((path, meta.get('noindex'), render(page(meta, body, lang, page_paths))))
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SRC / 'assets', OUT / 'assets')
    shutil.copytree(SRC / 'download', OUT / 'download')
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
