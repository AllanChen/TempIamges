"""Render the four localized Shizuka homepages from the current Figma copy.

Design direction: Shizuka / Sumi and Washi. Unslop by Damir Sokolovsky,
https://heydamir.design/unslop (CC BY 4.0).
"""
import json
from html import escape
from pathlib import Path

SRC = Path(__file__).resolve().parent / 'src'
COPY = json.loads((SRC / 'homepage.json').read_text())['languages']


def text(value):
    return escape(value).replace('\n', '<br>')


def artwork(kind, lang):
    parts = []
    for theme in ('dark', 'light'):
        for size in ('desktop', 'mobile'):
            html = (SRC / f'artwork/{kind}-{theme}-{size}.html').read_text()
            # These are the only words inside the otherwise static native chrome.
            labels = {'Portrait collection': ('人像照片集', 'ポートレート集', 'Porträtsammlung'),
                      '8 original photos': ('8 张原始照片', '8枚の元画像', '8 Originalfotos'),
                      'Compare images': ('对比图片', '画像を比較', 'Bilder vergleichen'),
                      '8s · Product demo': ('8 秒 · 产品演示', '8秒 · 製品デモ', '8 s · Produktdemo')}
            for en, translations in labels.items():
                html = html.replace(en, escape(dict(zip(('zh', 'ja', 'de'), translations)).get(lang, en)))
            parts.append(f'<div class="art-variant art-{theme} art-{size}">{html}</div>')
    return ''.join(parts)


# Screen readers and search engines read the product name as part of the main heading;
# the visible two-line headline stays exactly as designed.
BRAND_PREFIX = {"zh": "Glance Preview：", "en": "Glance Preview: ", "ja": "Glance Preview：", "de": "Glance Preview: "}


def render_home(lang, snapshot, dmg, version, size, checksum):
    sections = COPY[lang]['sections']
    def section(prefix):
        return next(s for s in sections if s['name'].startswith(prefix))['texts']
    def value(rows, key):
        return next(v for k, v in rows if k == key)
    def get(rows, key):
        return text(value(rows, key))
    def label(rows):
        return f'<p class="home-label">{get(rows, "Section label")}</p>'
    def download(rows):
        button = next(v for k, v in rows if k in ('Download for Mac', '下载 Mac 版', '下载 Mac 版 →') or k.startswith('Download'))
        return f'<a class="btn btn-primary" href="{dmg}">{text(button)} <span aria-hidden="true">↓</span></a>'
    play, pause = {'zh': ('播放演示', '暂停演示'), 'en': ('Play demo', 'Pause demo'), 'ja': ('デモを再生', 'デモを一時停止'), 'de': ('Demo abspielen', 'Demo pausieren')}[lang]
    def media(key):
        base = f'/assets/video/widgets/{key}-{lang}'
        attrs = ''
        compare = key == 'compare'
        if compare:
            for theme, source in (('dark', 'sumi'), ('light', 'washi')):
                for device in ('desktop', 'mobile'):
                    attrs += f' data-{theme}-{device}="{base}-{source}-{device}"'
            base += '-sumi-desktop'
        controls = json.loads((SRC / 'artwork/controls.json').read_text())
        if compare:
            icon = ''
            for theme in ('dark', 'light'):
                for device in ('desktop', 'mobile'):
                    dimensions = 14 if device == 'mobile' else 28
                    item = controls[f'compare-{theme}-{device}']
                    icon += f'<span class="art-variant art-{theme} art-{device}"><img class="play-icon" src="{item["play"]}" alt="" width="{dimensions}" height="{dimensions}"><img class="pause-icon" src="{item["pause"]}" alt="" width="{dimensions}" height="{dimensions}"></span>'
        else:
            item = controls['widget-playing']
            icon = f'<img class="play-icon" src="{item["play"]}" alt="" width="72" height="72"><img class="pause-icon" src="{item["pause"]}" alt="" width="44" height="44">'
        return (f'<figure class="promo-media{ " promo-compare" if compare else ""}" data-promo{attrs}>'
                + (artwork('compare', lang) if compare else '')
                + f'<video muted loop playsinline controls preload="none" width="720" height="{400 if compare else 480}" '
                  f'src="{base}.mp4" poster="{base}-poster.jpg" aria-label="{escape(play)}">'
                  f'<a href="{base}.mp4">{escape(play)}</a></video>'
                  f'<button class="promo-control" type="button" hidden data-play="{escape(play)}" data-pause="{escape(pause)}" aria-label="{escape(play)}" aria-pressed="false">{icon}<span class="control-label">{escape(play)}</span></button></figure>')
    h = section('02 ')
    out = [f'<div class="home-page"><section class="home-hero wrap">{label(h)}<div class="home-hero-grid"><div class="home-hero-copy"><h1><span class="visually-hidden">{escape(BRAND_PREFIX.get(lang, "Glance Preview: "))}</span>{get(h,"Hero headline")}</h1><p class="home-lead">{get(h,"Hero description")}</p><div class="home-actions">{download(h)}<a href="/#loop">{get(h,"Link / Widget demonstrations")}</a></div></div><div class="home-product" role="img" aria-label="{escape(value(h,"Product caption"))}">{artwork("hero",lang)}<p class="product-caption">{get(h,"Product caption")}</p></div></div><div class="home-facts">' + ''.join(f'<span>{get(h,f"Free start fact {i}")}</span>' for i in range(1,4)) + '</div></section>']
    intro = section('03 ')
    out.append(f'<section id="loop" class="home-intro wrap"><div>{label(intro)}<h2>{get(intro,"Workflow headline")}</h2></div><p>{get(intro,"Workflow introduction")}</p></section>')
    for i, (prefix, key) in enumerate((('04.1','background'), ('04.2','compare'), ('04.3','expand'), ('06 ','outfit'))):
        rows = section(prefix)
        out.append(f'<section class="home-story wrap {"story-reverse" if i%2 else ""}"><div class="story-copy"><p class="home-label">{get(rows,"Widget metadata")}</p><h2>{get(rows,"Widget headline")}</h2><p>{get(rows,"Widget explanation")}</p></div>{media(key)}</section>')
        if key == 'outfit':
            out.append(f'<aside class="home-more wrap"><p>{get(rows,"More Widget capabilities")}</p><a href="/widgets/">{get(rows,"Browse all Widgets")}</a><p class="home-disclosure">{get(rows,"Cloud processing disclosure")}</p></aside>')
    rows = section('05 ')
    names = [(k,v) for k,v in rows if k.startswith('Tool name /')]
    out.append(f'<section class="home-local wrap">{label(rows)}<h2>{get(rows,"More tools headline")}</h2><div class="home-ocr"><div><p class="home-label">{text([v for k,v in rows if k=="Section label"][1])}</p><h3>{get(rows,"OCR headline")}</h3><p>{get(rows,"OCR description")}</p></div><ol>' + ''.join(f'<li><span>0{i}</span>{get(rows,f"OCR instruction {i}")}{" <kbd>⌘C</kbd>" if i==3 else ""}</li>' for i in range(1,4)) + '</ol></div><div class="home-tool-grid">' + ''.join(f'<article><h3>{text(v)}</h3><p>{get(rows,k.replace("Tool name /","Tool description /"))}</p></article>' for k,v in names) + '</div></section>')
    rows = section('07 ')
    pricing = snapshot['pricing']
    cur = {'zh':'CNY','en':'USD','ja':'JPY','de':'EUR'}[lang]
    def price(item):
        amount = item[cur]['amount']
        if cur == 'JPY': return f'¥{amount:,}'
        n = f'{amount/100:.2f}'.rstrip('0').rstrip('.')
        return n.replace('.',',')+' €' if cur == 'EUR' else ('¥' if cur=='CNY' else '$')+n
    prices = [price({cur:{'amount':0}}), price(next(t for t in pricing['proTiers'] if t['id']=='personal')), price(next(t for t in pricing['packs'] if t['id']=='small'))]
    out.append(f'<section class="home-pricing wrap">{label(rows)}<h2>{get(rows,"Pricing headline")}</h2><p>{get(rows,"Pricing introduction")}</p><div class="home-plans">')
    plan_names = [v for k,v in rows if k.startswith('Plan name /')]
    links = [v for k,v in rows if k.startswith('Link /')]
    for i in range(3):
        out.append(f'<article><h3>{text(plan_names[i])}</h3><p class="home-price" data-home-price="{i}">{text(prices[i])}</p><p class="plan-term">{get(rows,f"Plan term / {i}")}</p><p>{get(rows,f"Plan description / {i}")}</p><a href="{dmg if i==0 else "/pricing/"}">{text(links[i])}</a></article>')
    out.append(f'</div><p class="home-disclosure">{get(rows,"Pricing disclosure")}</p><script id="home-pricing" type="application/json">{json.dumps(pricing).replace("<", chr(92)+"u003c")}</script></section>')
    rows = section('08 ')
    guide = next(v for k,v in rows if k.startswith('Link /'))
    out.append(f'<section id="download" class="home-download wrap"><div>{label(rows)}<h2>{get(rows,"Download headline")}</h2></div><div><p>{get(rows,"Download description")}</p><div class="home-actions">{download(rows)}<a href="/install/">{text(guide)}</a></div><p class="home-disclosure">{text(value(rows,"Download system requirements").replace("1.0.4",version))} · {size}</p><p class="home-disclosure">'+{'zh':'已通过 Apple 公证','en':'Notarized by Apple','ja':'Apple 公証済み','de':'Von Apple notarisiert'}[lang]+f'</p><details class="download-checksum"><summary>SHA-256</summary><code>{checksum}</code></details></div></section>')
    rows = section('09 ')
    questions = [v for k,v in rows if k.startswith('Question /')]
    out.append(f'<section class="home-faq wrap">{label(rows)}<h2>{get(rows,"FAQ headline")}</h2><div class="home-faq-grid">'+''.join(f'<details><summary>{text(q)}</summary><p>{get(rows,f"Answer / {i}")}</p></details>' for i,q in enumerate(questions))+'</div></section></div>')
    return '\n'.join(out)
