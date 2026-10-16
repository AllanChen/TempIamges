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
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "public"
SITE = "https://glance.mcreator.ai"
SUPPORT_EMAIL = "support@mcreator.ai"
VERSION = "1.0.0-beta.1"
DMG = f"/download/Glance-{VERSION}.dmg"
UPDATED = "2026-10-16"
RUNTIME_VERSION = "2026-10-16-bilingual-media"

# Last published pricing. The live page replaces it with /api/v2/pricing,
# which is edited in Admin. Amounts are minor units (fen / cents).
PRICING_FALLBACK = {
    "trialDays": 14, "signupCredits": 100, "proBonusCredits": 100, "deviceLimit": 2,
    "offlineDays": 30, "updatesMonths": 12, "renewalMonths": 12,
    "pro": {"CNY": {"amount": None}, "USD": {"amount": None}, "launchCNY": {"amount": None},
            "launchUSD": {"amount": None}, "launchUntil": None},
    "renewal": {"CNY": {"amount": None}, "USD": {"amount": None}},
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


def bi(zh: str, en: str, tag: str = "span") -> str:
    return f'<{tag} lang="zh">{zh}</{tag}><{tag} lang="en">{en}</{tag}>'


def header(active: str) -> str:
    links = "".join(
        f'<a class="hide-sm" href="{href}"{" aria-current=\"page\"" if key == active else ""}>{bi(zh, en)}</a>'
        for key, href, zh, en in NAV)
    return f"""<a class="skip" href="#main">{bi("跳到正文", "Skip to content")}</a>
<header class="site-header"><div class="wrap">
  <a class="brand" href="/"><img src="/assets/img/logo-256.png" alt="" width="30" height="30">Glance</a>
  <nav class="nav" aria-label="Main">{links}
    <button class="lang-toggle" type="button" aria-label="Switch language">{bi("EN", "中文")}</button>
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


def page(meta: dict, body: str) -> str:
    title_zh = f'{meta["zh"]} · Glance' if meta["path"] != "/" else "Glance · AI 时代的 Preview"
    title_en = f'{meta["en"]} · Glance' if meta["path"] != "/" else "Glance · The Preview for the AI era"
    desc = meta.get("desc", "Glance 是 macOS 上的看图看视频工具：不满意就地用 AI 改，改完对比确认。"
                            "Glance is a macOS image and video viewer with in-place AI fixes and side-by-side compare.")
    canonical = SITE + meta["path"]
    robots = '<meta name="robots" content="noindex">' if meta.get("noindex") else ""
    return f"""<!doctype html>
<html lang="zh-CN" data-lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_zh}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{canonical}">
<meta property="og:title" content="{title_zh} | {title_en}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="{SITE}/assets/video/glance-demo-poster.jpg?v=222cee43">
<meta property="og:url" content="{canonical}">
<meta name="theme-color" content="#08090c">
{robots}
<link rel="icon" type="image/png" href="/assets/img/favicon-64.png">
<link rel="apple-touch-icon" href="/assets/img/logo-256.png">
<script>(function(){{var l;try{{l=localStorage.getItem('glance.lang')}}catch(e){{}}if(!l)l=/^zh/i.test(navigator.language||'')?'zh':'en';document.documentElement.setAttribute('data-lang',l);document.documentElement.setAttribute('lang',l==='zh'?'zh-CN':'en')}})();</script>
<link rel="stylesheet" href="/assets/site.css?v={UPDATED}">
</head>
<body>
<span hidden data-title-zh="{title_zh}" data-title-en="{title_en}"></span>
{header(meta.get("nav", ""))}
<main id="main">
{body}
</main>
{footer()}
<script src="/assets/site.js?v={RUNTIME_VERSION}" defer></script>
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


def dmg_facts() -> tuple[str, str]:
    import hashlib
    path = SRC / DMG.lstrip("/")
    if not path.exists():
        raise SystemExit(f"Missing download: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return f"{path.stat().st_size / 1_000_000:.1f} MB", digest


DMG_SIZE, DMG_SHA256 = dmg_facts()


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SRC / "assets", OUT / "assets")
    shutil.copytree(SRC / "download", OUT / "download")
    paths = []
    for source in sorted((SRC / "pages").glob("*.html")):
        raw = source.read_text(encoding="utf-8")
        match = re.match(r"<!--(.*?)-->\s*", raw, re.S)
        if not match:
            raise SystemExit(f"{source.name}: missing metadata comment")
        meta = dict(part.split(":", 1) for part in (p.strip() for p in match.group(1).split("|")) if part)
        meta = {k.strip(): v.strip() for k, v in meta.items()}
        if "noindex" in meta:
            meta["noindex"] = meta["noindex"] == "true"
        html = render(page(meta, raw[match.end():]))
        if meta["path"] == "/404":
            target = OUT / "404.html"
        else:
            target = OUT / meta["path"].strip("/") / "index.html"
            if not meta.get("noindex"):
                paths.append(meta["path"])
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
""", encoding="utf-8")
    (OUT / "_redirects").write_text(f"""/refund /refunds/ 301
/refund/ /refunds/ 301
/Glance-1.0.0.dmg {DMG} 302
/download {DMG} 302
/download/ {DMG} 302
/aup /acceptable-use/ 301
""", encoding="utf-8")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /\nDisallow: /pay/\nSitemap: {SITE}/sitemap.xml\n", encoding="utf-8")
    urls = "".join(f"<url><loc>{SITE}{p}</loc><lastmod>{UPDATED}</lastmod></url>" for p in paths)
    (OUT / "sitemap.xml").write_text(
        f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>\n',
        encoding="utf-8")
    print(f"Built {len(list(OUT.rglob('index.html')))} pages into {OUT}")


if __name__ == "__main__":
    main()
