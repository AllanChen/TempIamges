"""Blog and Use Cases for the Glance site (English, plus translated copies).

Each English post is ONE file in src/posts/*.html, starting with a metadata comment:
  <!-- slug: my-post | kind: use-case | status: review | date: 2026-10-29
       | title: <title tag> | h1: <visible H1> | description: <meta description>
       | related: AI Widgets=/en/widgets/, Compare two images=/en/compare-images-mac/ -->
kind:   blog -> /en/blog/<slug>/      use-case -> /en/use-cases/<slug>/
status: published -> indexable, listed, in the sitemap
        review    -> rendered with noindex, NOT listed, NOT in the sitemap
FAQ:    put <section class="post-faq"> with <h3>Question</h3><p>Answer</p> pairs in the
        body; the FAQPage JSON-LD is generated from it.

Translations live in src/i18n/<lang>/posts/<same file name>.html with the SAME
metadata keys (slug and kind must match an English post; title, h1,
description, related and body are localized). They render at
/<lang>/blog/<slug>/ and /<lang>/use-cases/<slug>/. A post's hreflang cluster
is English plus every PUBLISHED translation, with x-default -> English.
Posts have no Chinese twin.
"""
from __future__ import annotations

import json
import math
import os
import re
from html import escape, unescape

KINDS = {
    "blog": ("/en/blog/", "Blog", "Glance Preview Blog",
             "Notes on previewing images on Mac and fixing them with one-click AI tools in Glance Preview."),
    "use-case": ("/en/use-cases/", "Use cases", "Glance Preview Use Cases",
                 "Step-by-step use cases for Glance Preview: preview an image on your Mac, fix it with a one-click AI tool, and compare the result with the original."),
}
# Per-language strings. "kinds" mirrors KINDS: (label, index title, index description).
STRINGS = {
    "en": {"kinds": {k: v[1:] for k, v in KINDS.items()}, "home": "Home", "min": "{n} min read",
           "empty": "The first posts are on the way.",
           "also": 'Also see <a href="{other}">{other_label}</a>, the <a href="/en/compare-images-mac/">image comparison guide</a> and the <a href="/en/widgets/">AI Widgets</a> list.',
           "try": "Try it on your own images",
           "try_p": "Glance Preview is a free beta for Apple silicon Macs (macOS 12.3 or later). AI tools run in the cloud and use credits; new accounts start with 100.",
           "cta": "Download Glance Preview", "related": "Related"},
    "ja": {"kinds": {
               "blog": ("ブログ", "Glance Preview ブログ",
                        "Mac での画像プレビューと、ワンクリック AI ツールでの画像補正についてのメモ。"),
               "use-case": ("使い方", "Glance Preview の使い方",
                            "Mac で画像をプレビューし、ワンクリック AI ツールで直して元画像と比べる、Glance Preview の手順ガイド。")},
           "home": "ホーム", "min": "約 {n} 分で読めます", "empty": "最初の記事を準備中です。",
           "also": '<a href="{other}">{other_label}</a>、<a href="/ja/compare-images-mac/">画像比較ガイド</a>、<a href="/ja/widgets/">AI ウィジェット一覧</a>もご覧ください。',
           "try": "手元の画像で試してみる",
           "try_p": "Glance Preview は Apple シリコン搭載 Mac（macOS 12.3 以降）向けの無料ベータ版です。アプリの表示言語は英語と簡体字中国語のみです。AI ツールはクラウドで動作しクレジットを使います。新規アカウントには 100 クレジットが付きます。",
           "cta": "Glance Preview をダウンロード", "related": "関連記事"},
    "de": {"kinds": {
               "blog": ("Blog", "Glance Preview Blog",
                        "Notizen zur Bildvorschau auf dem Mac und zum Bearbeiten von Bildern mit KI-Werkzeugen per Klick in Glance Preview."),
               "use-case": ("Anwendungsfälle", "Glance Preview: Anwendungsfälle",
                            "Schritt-für-Schritt-Anleitungen für Glance Preview: Bild auf dem Mac ansehen, mit einem KI-Werkzeug per Klick korrigieren und mit dem Original vergleichen.")},
           "home": "Start", "min": "{n} Min. Lesezeit", "empty": "Die ersten Beiträge sind in Arbeit.",
           "also": 'Siehe auch <a href="{other}">{other_label}</a>, die <a href="/de/compare-images-mac/">Anleitung zum Bildvergleich</a> und die Liste der <a href="/de/widgets/">KI-Widgets</a>.',
           "try": "Mit eigenen Bildern ausprobieren",
           "try_p": "Glance Preview ist eine kostenlose Beta für Macs mit Apple Silicon (macOS 12.3 oder neuer). Die App-Oberfläche gibt es nur auf Englisch und vereinfachtem Chinesisch. KI-Werkzeuge laufen in der Cloud und verbrauchen Credits; neue Konten starten mit 100.",
           "cta": "Glance Preview herunterladen", "related": "Weiterlesen"},
}
REQUIRED = ("slug", "kind", "status", "date", "title", "h1", "description")
PREVIEW = os.environ.get("GLANCE_PREVIEW") == "1"   # list review posts in indexes (local preview only)


def base_for(lang: str, kind: str) -> str:
    return f"/{lang}" + KINDS[kind][0][3:]


def load_posts(folder, lang: str = "en") -> list[dict]:
    posts, seen = [], set()
    for source in sorted(folder.glob("*.html")):
        raw = source.read_text(encoding="utf-8")
        match = re.match(r"<!--(.*?)-->\s*", raw, re.S)
        if not match:
            raise SystemExit(f"{source.name}: missing metadata comment")
        meta = {k.strip(): v.strip() for k, v in
                (part.split(":", 1) for part in (p.strip() for p in re.split(r"\|\s*(?=[a-z0-9_]+:)", match.group(1))) if part)}
        missing = [k for k in REQUIRED if not meta.get(k)]
        if missing:
            raise SystemExit(f"{source.name}: missing {missing}")
        if meta["kind"] not in KINDS or meta["status"] not in ("published", "review"):
            raise SystemExit(f"{source.name}: bad kind or status")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", meta["date"]):
            raise SystemExit(f"{source.name}: date must be YYYY-MM-DD")
        meta["lang"] = lang
        meta["path"] = base_for(lang, meta["kind"]) + meta["slug"] + "/"
        if meta["path"] in seen:
            raise ValueError(f"Duplicate post path {meta['path']}")
        seen.add(meta["path"])
        meta["related"] = [r.strip() for r in meta.get("related", "").split(",") if r.strip()]
        meta["body"] = raw[match.end():]
        meta["source"] = source.name
        text = re.sub(r"<[^>]+>", " ", re.sub(r"<!--.*?-->", " ", meta["body"], flags=re.S))
        # CJK has no spaces: count ~500 characters per minute for Japanese.
        meta["minutes"] = max(1, math.ceil(len(re.sub(r"\s", "", text)) / 500) if lang == "ja"
                              else math.ceil(len(text.split()) / 220))
        meta["faq"] = [(re.sub(r"<[^>]+>", "", unescape(q)).strip(), re.sub(r"<[^>]+>", "", unescape(a)).strip())
                       for q, a in re.findall(r"<h3>(.*?)</h3>\s*<p>(.*?)</p>",
                                              (re.search(r'<section class="post-faq".*?</section>', meta["body"], re.S) or re.match("", "")).group(0), re.S)]
        posts.append(meta)
    return posts


def ld(data) -> str:
    return '<script type="application/ld+json">' + json.dumps(data, ensure_ascii=False).replace("<", "\\u003c") + "</script>"


def shell(b, path, title, desc, body, schema="", noindex=False, og_type="website", lang="en", cluster=None) -> str:
    """cluster: {lang: path} of indexable versions; x-default is English."""
    url = b.SITE + path
    t, d = escape(title, quote=True), escape(desc, quote=True)
    robots = '<meta name="robots" content="noindex">' if noindex else ""
    cluster = cluster or {lang: path}
    alt = "" if noindex else "\n".join(
        [f'<link rel="alternate" hreflang="{b.LANGUAGES[c][2]}" href="{b.SITE}{p}">' for c, p in cluster.items()]
        + [f'<link rel="alternate" hreflang="x-default" href="{b.SITE}{cluster.get("en", path)}">'])
    return f"""<!doctype html>
<html lang="{b.LANGUAGES[lang][1]}" data-lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{t}</title>
<meta name="description" content="{d}">
<link rel="canonical" href="{url}">
{alt}
<meta property="og:title" content="{t}">
<meta property="og:description" content="{d}">
<meta property="og:type" content="{og_type}">
<meta property="og:locale" content="{b.LANGUAGES[lang][3]}">
<meta property="og:image" content="{b.SITE}/assets/video/glance-demo-poster-en.jpg">
<meta property="og:url" content="{url}">
<meta name="twitter:card" content="summary_large_image">
{schema}
<meta name="theme-color" content="#08090c">
{robots}
<link rel="icon" type="image/png" href="/assets/img/favicon-64.png">
<link rel="apple-touch-icon" href="/assets/img/logo-256.png">
<link rel="stylesheet" href="/assets/site.css?v={b.ASSET_VERSION}">
</head>
<body>
{{HEADER}}
<main id="main">
{body}
</main>
{{FOOTER}}
<script src="/assets/site.js?v={b.ASSET_VERSION}" defer></script>
</body>
</html>
"""


def wrap(b, html, page_paths, lang="en", cluster=None) -> str:
    # English toggles to the Chinese homepage (no zh twin); other languages
    # toggle to the English version and list their sibling translations.
    cluster = cluster or {}
    toggle = "/" if lang == "en" else cluster.get("en", "/en/")
    others = [(c, p) for c, p in cluster.items() if c not in (lang, "en")]
    translated = set(b.TRANSLATIONS[lang]) if lang in b.TRANSLATIONS else None
    html = html.replace("{HEADER}", b.localize(b.header("", toggle, others), lang, page_paths, translated), 1)
    html = html.replace("{FOOTER}", b.localize(b.footer(), lang, page_paths, translated), 1)
    # Same {{SUPPORT_X}} / {{VERSION}} / … placeholders as build.render() for pages.
    return b.render(html, lang)


def card(p) -> str:
    minutes = STRINGS[p["lang"]]["min"].format(n=p["minutes"])
    return (f'<article class="card post-card"><p class="small">{p["date"]} · {minutes}</p>'
            f'<h3><a href="{p["path"]}">{escape(p["h1"])}</a></h3><p>{escape(p["description"])}</p></article>')


def breadcrumb(b, items) -> dict:
    return {"@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": i + 1, "name": n, "item": b.SITE + u} for i, (n, u) in enumerate(items)]}


def load_all(b) -> dict[str, list[dict]]:
    posts = {"en": load_posts(b.SRC / "posts")}
    english = {(p["kind"], p["slug"]): p for p in posts["en"]}
    for lang in b.EXTRA_LANGUAGES:
        folder = b.SRC / "i18n" / lang / "posts"
        posts[lang] = load_posts(folder, lang) if folder.exists() else []
        for p in posts[lang]:
            if (p["kind"], p["slug"]) not in english:
                raise SystemExit(f"{lang}/posts/{p['source']}: no English post with kind {p['kind']} and slug {p['slug']}")
    return posts


def render_content(b, page_paths) -> list[tuple[str, bool, str]]:
    posts = load_all(b)
    live = lambda p: p["status"] == "published"
    # (kind, slug) -> {lang: path} of published versions, English first.
    clusters: dict = {}
    for lang, items in posts.items():
        for p in items:
            if live(p):
                clusters.setdefault((p["kind"], p["slug"]), {})[lang] = p["path"]
    out = []
    for lang, items in posts.items():
        S = STRINGS[lang]
        index_cluster = {c: base_for(c, "blog") for c in posts if c == "en" or posts[c]}
        for kind in KINDS:
            base = base_for(lang, kind)
            label, title, desc = S["kinds"][kind]
            if lang != "en" and not items:
                continue
            listed = sorted((p for p in items if p["kind"] == kind and (live(p) or PREVIEW)),
                            key=lambda p: p["date"], reverse=True)
            cards = "".join(card(p) for p in listed) or f'<p class="notice">{S["empty"]}</p>'
            other = [k for k in KINDS if k != kind][0]
            other_label = S["kinds"][other][0]
            also = S["also"].format(other=base_for(lang, other), other_label=other_label.lower() if lang == "en" else other_label)
            body = f"""<section class="hero guide-hero"><div class="wrap">
<p class="eyebrow">Glance Preview · {label}</p>
<h1>{escape(title)}</h1>
<p class="lead">{escape(desc)}</p>
</div></section>
<section class="guide-section" style="padding-top:0"><div class="narrow"><div class="post-list">{cards}</div>
<p class="guide-note">{also}</p></div></section>"""
            schema = ld({"@context": "https://schema.org", "@graph": [
                {"@type": "CollectionPage", "name": title, "url": b.SITE + base, "description": desc, "inLanguage": lang},
                breadcrumb(b, [(S["home"], f"/{lang}/"), (label, base)])]})
            cluster = {c: base_for(c, kind) for c in index_cluster}
            out.append((base, False, wrap(b, shell(b, base, f"{title} · Glance", desc, body, schema, lang=lang,
                                                   cluster=cluster), page_paths, lang, cluster)))
        for p in items:
            base = base_for(lang, p["kind"])
            label = S["kinds"][p["kind"]][0]
            cluster = clusters.get((p["kind"], p["slug"]), {}) if live(p) else {}
            siblings = [q for q in items if q is not p and q["kind"] == p["kind"] and live(q)][:3]
            related = "".join(f'<li><a href="{u.strip()}">{escape(n.strip())}</a></li>' for n, u in (r.split("=", 1) for r in p["related"]))
            related += "".join(f'<li><a href="{q["path"]}">{escape(q["h1"])}</a></li>' for q in siblings)
            body = f"""<article class="post">
<section class="hero guide-hero"><div class="wrap">
<p class="eyebrow"><a href="{base}">{label}</a></p>
<h1>{escape(p["h1"])}</h1>
<p class="small post-meta"><time datetime="{p["date"]}">{p["date"]}</time> · {S["min"].format(n=p["minutes"])} · Glance Preview</p>
</div></section>
<section class="guide-section post-body" style="padding-top:0"><div class="narrow">
{p["body"]}
</div></section>
<section class="guide-section guide-end"><div class="narrow">
<h2>{S["try"]}</h2>
<p>{S["try_p"]}</p>
<p><a class="btn btn-primary" href="/{lang}/install/">{S["cta"]}</a></p>
{f'<h3>{S["related"]}</h3><ul class="post-related">{related}</ul>' if related else ''}
</div></section>
</article>"""
            graph = [{"@type": "Article", "headline": p["h1"], "description": p["description"],
                      "datePublished": p["date"], "dateModified": p.get("updated", p["date"]),
                      "inLanguage": lang, "mainEntityOfPage": b.SITE + p["path"],
                      "author": {"@type": "Organization", "name": "Glance", "url": b.SITE + "/"},
                      "publisher": {"@id": b.SITE + "/#organization"},
                      "image": b.SITE + "/assets/video/glance-demo-poster-en.jpg"},
                     breadcrumb(b, [(S["home"], f"/{lang}/"), (label, base), (p["h1"], p["path"])])]
            if p["faq"]:
                graph.append({"@type": "FAQPage", "mainEntity": [
                    {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in p["faq"]]})
            html = shell(b, p["path"], p["title"], p["description"], body,
                         ld({"@context": "https://schema.org", "@graph": graph}), not live(p), "article", lang, cluster)
            out.append((p["path"], not live(p), wrap(b, html, page_paths, lang, cluster)))
    return out
