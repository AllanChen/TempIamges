"""Non-UI release checks: python3 -m unittest discover -s website/static -p 'test_*.py'."""
import tempfile
import re
import json
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
from urllib.robotparser import RobotFileParser
import xml.etree.ElementTree as ET

import build
import content
from localize import localize


class Document(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.nodes = []
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        self.nodes.append((tag, dict(attrs)))

    def select(self, tag, **attrs):
        return [a for t, a in self.nodes if t == tag and all(a.get(k) == v for k, v in attrs.items())]


class SiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pages = {('/' + str(p.relative_to(build.OUT)).removesuffix('index.html')): Document(p)
                     for p in build.OUT.rglob('index.html')}
        cls.sitemap = [n.text for n in ET.parse(build.OUT/'sitemap.xml').findall('.//{*}loc')]

    def test_languages_canonicals_and_alternates(self):
        posts = content.load_posts(build.SRC/'posts')
        everything = content.load_all(build)
        english_only = {base for base, *_ in content.KINDS.values()}
        content_pages = {p['path'] for ps in everything.values() for p in ps if p['status'] == 'published'}
        content_pages |= {content.base_for(lang, kind) for lang, ps in everything.items() if lang != 'en' and ps for kind in content.KINDS}
        extra = sum(len(pages) for pages in build.TRANSLATIONS.values())
        self.assertEqual(len(self.sitemap), 22 + extra + len(english_only) + len(content_pages - english_only))
        english_only |= content_pages
        self.assertEqual(len(set(self.sitemap)), len(self.sitemap))
        for url in self.sitemap:
            if urlsplit(url).path in english_only:
                continue
            with self.subTest(url=url):
                path = urlsplit(url).path
                doc = self.pages[path]
                language = next((code for code in build.EXTRA_LANGUAGES + ['en'] if path.startswith('/'+code+'/')), 'zh')
                base = path.removeprefix(build.LANGUAGES[language][0])
                self.assertEqual(doc.select('html')[0]['lang'], build.LANGUAGES[language][1])
                self.assertEqual(len(doc.select('h1')), 1)
                self.assertEqual(doc.select('link', rel='canonical')[0]['href'], url)
                self.assertFalse(doc.select('meta', name='robots'))
                self.assertFalse(any(a.get('lang') in build.LANGUAGES and a.get('lang') != language for _, a in doc.nodes))
                alternates = {a['hreflang']: a['href'] for a in doc.select('link', rel='alternate')}
                self.assertEqual(set(alternates), {build.LANGUAGES[code][2] for code in build.languages_for(base)} | {'x-default'})
                for target in alternates.values():
                    self.assertIn(target, self.sitemap)
                    other = self.pages[urlsplit(target).path]
                    self.assertEqual(alternates, {a['hreflang']: a['href'] for a in other.select('link', rel='alternate')})
                switch = doc.select('a', **{'class': 'lang-toggle'})[0]['href']
                self.assertEqual(switch, base if language == 'en' else '/en'+base)

    def test_extra_language_hreflang_and_links(self):
        for lang, locale in (('ja', 'ja_JP'), ('de', 'de_DE')):
            for base in ('/', '/install/', '/pricing/', '/widgets/', '/ai-models/', '/compare-images-mac/', '/copy-text-from-image-mac/'):
                self.assertIn(base, build.TRANSLATIONS[lang])
            for base in build.TRANSLATIONS[lang]:
                with self.subTest(lang=lang, base=base):
                    cluster = {}
                    for code in build.languages_for(base):
                        doc = self.pages[build.url_for(code, base)]
                        cluster[code] = {a['hreflang']: a['href'] for a in doc.select('link', rel='alternate')}
                        self.assertEqual(cluster[code]['x-default'], build.SITE + '/en' + base)
                        self.assertEqual(cluster[code][lang], build.SITE + '/' + lang + base)
                        self.assertEqual(cluster[code]['zh-Hans'], build.SITE + base)
                    self.assertEqual(len({tuple(sorted(c.items())) for c in cluster.values()}), 1)
                    page = self.pages['/' + lang + base]
                    self.assertEqual(page.select('meta', property='og:locale')[0]['content'], locale)
                    html = (build.OUT/lang/base.strip('/')/'index.html').read_text()
                    self.assertNotRegex(re.sub(r'<script.*?</script>', '', html, flags=re.S), r'[，图载这们说为简]')  # simplified-Chinese leak
                    self.assert_links_resolve(page, lang)
                    # zh and en pages link to the translation in the switcher.
                    for other in ('zh', 'en'):
                        self.assertTrue(self.pages[build.url_for(other, base)].select('a', href='/' + lang + base, hreflang=build.LANGUAGES[lang][2]))
        # Untranslated pages carry no extra-language alternate.
        untranslated = next(p for p in self.pages if p.startswith('/en/') and p.removeprefix('/en') not in build.TRANSLATIONS['ja'] and p.removeprefix('/en') in build.TRANSLATIONS.get('zh', self.pages) and not p.startswith(('/en/blog', '/en/use-cases')))
        self.assertNotIn('ja', {a['hreflang'] for a in self.pages[untranslated].select('link', rel='alternate')})

    def assert_links_resolve(self, doc, lang):
        for _, attrs in doc.nodes:
            href = attrs.get('href', '')
            if href.startswith('/') and not href.startswith(('/assets/', '/download/')):
                path = urlsplit(href).path
                self.assertIn(path, self.pages, href)
                if not attrs.get('hreflang'):
                    self.assertTrue(path.startswith(('/' + lang + '/', '/en/')), href)

    def test_translated_posts_and_indexes(self):
        english = {p['slug']: p for p in content.load_posts(build.SRC/'posts') if p['status'] == 'published'}
        for lang in ('ja', 'de'):
            posts = content.load_posts(build.SRC/'i18n'/lang/'posts', lang)
            self.assertEqual({p['slug'] for p in posts}, set(english), lang)
            for kind in content.KINDS:
                index = content.base_for(lang, kind)
                self.assertIn(build.SITE + index, self.sitemap)
                doc = self.pages[index]
                self.assertEqual(doc.select('html')[0]['lang'], lang)
                for p in posts:
                    if p['kind'] == kind:
                        if p['status'] == 'published':
                            self.assertTrue(doc.select('a', href=p['path']), p['path'])
                        elif not content.PREVIEW:
                            self.assertFalse(doc.select('a', href=p['path']), p['path'])
            for post in posts:
                if post['status'] != 'published':
                    # Translations awaiting Allan's review: rendered noindex, unlisted, outside sitemap and hreflang.
                    with self.subTest(lang=lang, review=post['slug']):
                        doc = self.pages[post['path']]
                        self.assertEqual(doc.select('meta', name='robots')[0]['content'], 'noindex')
                        self.assertNotIn(build.SITE + post['path'], self.sitemap)
                        en_alt = {a['hreflang']: a['href'] for a in self.pages[english[post['slug']]['path']].select('link', rel='alternate')}
                        self.assertNotIn(build.SITE + post['path'], en_alt.values())
                        self.assertRegex(post['body'], {'ja': '英語・簡体字中国語・日本語', 'de': 'Englisch, vereinfachtem Chinesisch und Deutsch'}[lang])
                        self.assert_links_resolve(doc, lang)
                    continue
                with self.subTest(lang=lang, post=post['slug']):
                    en = english[post['slug']]
                    self.assertEqual(post['kind'], en['kind'])
                    self.assertNotEqual(post['title'], en['title'])
                    doc = self.pages[post['path']]
                    self.assertTrue(post['path'].startswith('/' + lang + '/'))
                    self.assertEqual(doc.select('html')[0]['lang'], lang)
                    self.assertEqual(len(doc.select('h1')), 1)
                    self.assertEqual(doc.select('link', rel='canonical')[0]['href'], build.SITE + post['path'])
                    alternates = {a['hreflang']: a['href'] for a in doc.select('link', rel='alternate')}
                    self.assertEqual(alternates['x-default'], build.SITE + en['path'])
                    self.assertEqual(alternates[lang], build.SITE + post['path'])
                    self.assertEqual(alternates, {a['hreflang']: a['href'] for a in self.pages[en['path']].select('link', rel='alternate')})
                    self.assertIn(build.SITE + post['path'], self.sitemap)
                    self.assertTrue(post['faq'])
                    # Honest about the app UI language.
                    self.assertRegex(post['body'], {'ja': '英語・簡体字中国語・日本語', 'de': 'Englisch, vereinfachtem Chinesisch und Deutsch'}[lang])
                    html = (build.OUT/post['path'].strip('/')/'index.html').read_text()
                    self.assertNotRegex(re.sub(r'<script.*?</script>', '', html, flags=re.S), r'[，图载这们说为简]')
                    self.assertIn('FAQPage', html)
                    self.assert_links_resolve(doc, lang)

    def test_english_only_blog_and_use_cases(self):
        posts = content.load_posts(build.SRC/'posts')
        for base, *_ in content.KINDS.values():
            self.assertIn(build.SITE+base, self.sitemap)
            self.assertNotIn(base.removeprefix('/en'), self.pages)
        for post in posts:
            with self.subTest(post=post['source']):
                doc = self.pages[post['path']]
                html = (build.OUT/post['path'].strip('/')/'index.html').read_text()
                self.assertEqual(len(doc.select('h1')), 1)
                self.assertEqual(doc.select('link', rel='canonical')[0]['href'], build.SITE+post['path'])
                self.assertTrue(doc.select('a', href='/en/install/'))
                graph = json.loads(re.search(r'<script type="application/ld\+json">(.*?)</script>', html, re.S).group(1))['@graph']
                types = {item['@type'] for item in graph}
                self.assertIn('Article', types)
                if post['faq']:
                    self.assertIn('FAQPage', types)
                for word in (' only ', ' first ', ' best ', ' unique ', 'tell AI', 'tell the AI'):
                    visible = re.sub(r'<!--.*?-->', '', post['body'], flags=re.S)
                    self.assertNotIn(word, visible.replace('\n', ' '), word)
                if post['status'] == 'published':
                    self.assertIn(build.SITE+post['path'], self.sitemap)
                    self.assertFalse(doc.select('meta', name='robots'))
                    self.assertNotRegex(post['body'], r'\[(VERIFY|TEST NEEDED|ASSET NEEDED)')
                    alternates = {a['hreflang']: a['href'] for a in doc.select('link', rel='alternate')}
                    self.assertEqual(alternates['en'], build.SITE+post['path'])
                    self.assertEqual(alternates['x-default'], build.SITE+post['path'])
                    self.assertLessEqual(set(alternates), {'en', 'x-default', 'ja', 'de'})
                else:
                    self.assertNotIn(build.SITE+post['path'], self.sitemap)
                    self.assertEqual(doc.select('meta', name='robots')[0]['content'], 'noindex')
                    listing = (build.OUT/content.KINDS[post['kind']][0].strip('/')/'index.html').read_text()
                    if not content.PREVIEW:
                        self.assertNotIn(post['path'], listing)

    def test_internal_links_and_media_exist(self):
        for path, doc in self.pages.items():
            for tag, attrs in doc.nodes:
                for key in ('href', 'src', 'poster'):
                    if key not in attrs:
                        continue
                    url = urlsplit(attrs[key])
                    if url.scheme or url.netloc or not url.path and not url.fragment:
                        continue
                    target = url.path or path
                    with self.subTest(page=path, target=attrs[key]):
                        if target.endswith('/'):
                            self.assertIn(target, self.pages)
                        else:
                            self.assertTrue((build.OUT/target.lstrip('/')).is_file(), target)
                        if url.fragment and target in self.pages:
                            self.assertTrue(any(a.get('id') == url.fragment for _, a in self.pages[target].nodes), attrs[key])

    def test_noindex_return_is_crawlable_and_not_in_sitemap(self):
        path = '/pay/return/'
        self.assertNotIn(build.SITE+path, self.sitemap)
        self.assertEqual(self.pages[path].select('meta', name='robots')[0]['content'], 'noindex')
        robots = RobotFileParser()
        robots.parse((build.OUT/'robots.txt').read_text().splitlines())
        for suffix in ('', '?order=order_example'):
            self.assertTrue(robots.can_fetch('Googlebot', build.SITE+path+suffix))
        self.assertFalse(robots.can_fetch('Googlebot', build.SITE+'/pay/other/'))
        self.assertIn('X-Robots-Tag: noindex', (build.OUT/'_headers').read_text())

    def test_duplicate_source_route_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ('a.html', 'b.html'):
                (Path(folder)/name).write_text('<!-- path: / | zh: 首页 | en: Home -->\n<h1>Hi</h1>')
            with self.assertRaisesRegex(ValueError, 'Duplicate page path'):
                build.load_pages(Path(folder))

    def test_payment_callback_script_is_preserved(self):
        source = (build.SRC/'pages/50-payment-return.html').read_text()
        generated = (build.OUT/'pay/return/index.html').read_text()
        callback = re.search(r'<script>(.*?)</script>', source, re.S).group(1)
        self.assertIn('<script>'+callback+'</script>', generated)

    def test_localizer_keeps_scripts_and_nested_markup(self):
        script = '<script>const example = "<a lang=zh>"; const value = 1 < 2;</script>'
        source = '<div lang="zh"><p>中文<br><img src="/x"></p></div><div lang="en"><p>English &amp; <b>nested</b></p></div>'+script
        result = localize(source, 'en', {'/'})
        self.assertNotIn('中文', result)
        self.assertIn('English &amp; <b>nested</b>', result)
        self.assertIn(script, result)

    def test_localized_media_and_download(self):
        for path in ('/', '/en/'):
            video = self.pages[path].select('video')[0]
            lang = 'en' if path.startswith('/en/') else 'zh'
            self.assertEqual(video['src'], video['data-video-'+lang])
            self.assertEqual(video['poster'], video['data-poster-'+lang])
        for path in ('/install/', '/en/install/'):
            self.assertIn(build.DMG_SHA256, (build.OUT/path.strip('/')/'index.html').read_text())
            self.assertTrue(self.pages[path].select('a', href=build.DMG))

    def test_guides_and_public_snapshot_are_crawlable(self):
        for path in ('/compare-images-mac/', '/copy-text-from-image-mac/'):
            for language_path in (path, '/en' + path):
                with self.subTest(path=language_path):
                    self.assertIn(build.SITE + language_path, self.sitemap)
                    self.assertTrue(self.pages[language_path].select('ol', **{'class': 'guide-steps'}))
        for path in ('/widgets/', '/en/widgets/'):
            self.assertEqual(len(self.pages[path].select('article', **{'class': 'widget'})), len(build.SNAPSHOT['widgets']))
        english = (build.OUT/'en/widgets/index.html').read_text()
        self.assertIn('100 credits / 10 sec', english)
        for path in ('/pricing/', '/en/pricing/'):
            html = (build.OUT/path.strip('/')/'index.html').read_text()
            if not build.PRICING_FALLBACK['paymentsAvailable']:
                self.assertIn('data-tiers><p class="notice">', html)
                self.assertIn('data-packs><p class="notice">', html)

    def test_homepage_schema_matches_public_offer(self):
        for path in ('/', '/en/'):
            html = (build.OUT/path.strip('/')/'index.html').read_text()
            payload = re.search(r'<script type="application/ld\+json">(.*?)</script>', html, re.S)
            self.assertIsNotNone(payload)
            graph = json.loads(payload.group(1))['@graph']
            software = next(item for item in graph if item['@type'] == 'SoftwareApplication')
            self.assertEqual(software['downloadUrl'], build.SITE + build.DMG)
            self.assertEqual(software['offers']['price'], '0')


if __name__ == '__main__':
    unittest.main()
