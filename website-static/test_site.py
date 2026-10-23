"""Non-UI release checks: python3 -m unittest discover -s website-static -p 'test_*.py'."""
import tempfile
import re
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
        self.assertEqual(len(self.sitemap), 18)
        self.assertEqual(len(set(self.sitemap)), 18)
        for url in self.sitemap:
            with self.subTest(url=url):
                path = urlsplit(url).path
                doc = self.pages[path]
                language = 'en' if path.startswith('/en/') else 'zh'
                self.assertEqual(doc.select('html')[0]['lang'], 'en' if language == 'en' else 'zh-CN')
                self.assertEqual(len(doc.select('h1')), 1)
                self.assertEqual(doc.select('link', rel='canonical')[0]['href'], url)
                self.assertFalse(doc.select('meta', name='robots'))
                self.assertFalse(any(a.get('lang') == ('zh' if language == 'en' else 'en') for _, a in doc.nodes))
                alternates = {a['hreflang']: a['href'] for a in doc.select('link', rel='alternate')}
                self.assertEqual(set(alternates), {'en', 'zh-Hans', 'x-default'})
                for target in alternates.values():
                    self.assertIn(target, self.sitemap)
                    other = self.pages[urlsplit(target).path]
                    self.assertEqual(alternates, {a['hreflang']: a['href'] for a in other.select('link', rel='alternate')})
                switch = doc.select('a', **{'class': 'lang-toggle'})[0]['href']
                self.assertEqual(switch, path.removeprefix('/en') if language == 'en' else '/en'+path)

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


if __name__ == '__main__':
    unittest.main()
