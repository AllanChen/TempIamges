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
        self.assertEqual(len(self.sitemap), 24)
        self.assertEqual(len(set(self.sitemap)), 24)
        for url in self.sitemap:
            with self.subTest(url=url):
                path = urlsplit(url).path
                doc = self.pages[path]
                language = next((l for l in ('en', 'ja', 'de') if path.startswith('/' + l + '/')), 'zh')
                base = path.removeprefix('/' + language) if language != 'zh' else path
                self.assertEqual(doc.select('html')[0]['lang'], build.HTML_LANG[language])
                self.assertEqual(len(doc.select('h1')), 1)
                self.assertEqual(doc.select('link', rel='canonical')[0]['href'], url)
                self.assertFalse(doc.select('meta', name='robots'))
                self.assertFalse(any(a.get('lang') in {'zh', 'en', 'ja', 'de'} - {language} for _, a in doc.nodes))
                alternates = {a['hreflang']: a['href'] for a in doc.select('link', rel='alternate')}
                expected = {'en', 'zh-Hans', 'x-default'} | ({'ja', 'de'} if base == '/' else set())
                self.assertEqual(set(alternates), expected)
                for target in alternates.values():
                    self.assertIn(target, self.sitemap)
                    other = self.pages[urlsplit(target).path]
                    self.assertEqual(alternates, {a['hreflang']: a['href'] for a in other.select('link', rel='alternate')})
                options = {a['href'] for a in doc.select('a', **{'class': 'lang-option'})}
                self.assertEqual(options, {urlsplit(t).path for h, t in alternates.items() if h != 'x-default'})
                self.assertEqual([a['href'] for a in doc.select('a', **{'class': 'lang-option', 'aria-current': 'true'})], [path])

    def test_japanese_and_german_homepages(self):
        for lang in ('ja', 'de'):
            html = (build.OUT / lang / 'index.html').read_text()
            doc = self.pages['/' + lang + '/']
            with self.subTest(lang=lang):
                self.assertEqual(doc.select('html')[0]['data-lang'], lang)
                video = doc.select('video')[0]
                self.assertEqual(video['src'], video['data-video-en'])
                for tag, attrs in doc.nodes:
                    href = attrs.get('href', '') if tag == 'a' and attrs.get('class') != 'lang-option' else ''
                    if href.startswith('/') and not href.startswith('/download/') and urlsplit(href).path not in ('/', '/' + lang + '/'):
                        self.assertTrue(href.startswith('/en/'), href)
                self.assertTrue(doc.select('a', href='/' + lang + '/#download'))
                self.assertIn(build.SUPPORT_X_URL, html)
                self.assertIn(build.DMG_SHA256, html)
                self.assertEqual(len(doc.select('article', **{'class': 'widget'})), min(6, len(build.SNAPSHOT['widgets'])))
                self.assertNotIn('点 / ', html)
        for path, peek in (('/', None), ('/en/', None), ('/ja/', 'peek-ja'), ('/de/', 'peek-de')):
            sources = [a['src'] for a in self.pages[path].select('source')]
            tracks = [a['srclang'] for a in self.pages[path].select('track')]
            self.assertEqual([urlsplit(src).path for src in sources], [f'/assets/video/{peek}.mp4'] if peek else [])
            self.assertEqual(tracks, [peek[-2:]] if peek else [])
        self.assertIn('ダウンロード', (build.OUT / 'ja/index.html').read_text())
        self.assertIn('herunterladen', (build.OUT / 'de/index.html').read_text())

    def test_support_is_x_direct_message(self):
        for path in self.pages:
            html = (build.OUT / ('404.html' if path == '/404' else path.strip('/') + '/index.html')).read_text() if path != '/' else (build.OUT / 'index.html').read_text()
            with self.subTest(path=path):
                self.assertNotIn('mailto:', html)
                self.assertNotIn('support@', html)

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

    def test_release_copy_follows_dmg_and_sales_state(self):
        def body(path, flags):
            original = dict(build.FLAGS)
            build.FLAGS.update(flags)
            try:
                return next(b for m, b in build.load_pages(build.SRC / 'pages') if m['path'] == path)
            finally:
                build.FLAGS.clear(); build.FLAGS.update(original)
        release = {'beta': False, 'notarized': True, 'sales': True}
        for path in ('/', '/install/', '/pricing/', '/copy-text-from-image-mac/'):
            with self.subTest(path=path):
                text = body(path, release)
                self.assertNotIn('<!--if:', text)
                for stale in ('内测', 'beta', 'Beta', '尚未经过', '还没有经过', 'not yet notarized'):
                    self.assertNotIn(stale, text)
        self.assertIn('已通过 Apple 公证', body('/install/', release))
        self.assertIn('Notarized by Apple', body('/', release))
        unnotarized = body('/install/', {'beta': True, 'notarized': False})
        self.assertIn('还没有经过 Apple 公证', unnotarized)
        self.assertNotIn('已通过 Apple 公证', unnotarized)
        self.assertIn('内测说明', body('/pricing/', {'beta': True, 'sales': False}))
        with self.assertRaises(SystemExit):
            build.conditional('<!--if:unknown-->x<!--endif-->')
        with self.assertRaises(SystemExit):
            build.conditional('<!--if:beta-->x')

    def test_peek_permissions_match_app(self):
        for path in ('/install/', '/en/install/'):
            text = (build.OUT / path.strip('/') / 'index.html').read_text()
            with self.subTest(path=path):
                self.assertNotIn('「辅助功能」和「输入监控」两项权限', text)
                self.assertNotIn('Accessibility and Input Monitoring permissions', text)


if __name__ == '__main__':
    unittest.main()
