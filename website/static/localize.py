"""Produce one language of the bilingual HTML sources without browser scripting."""
from html import escape
from html.parser import HTMLParser
from urllib.parse import urlsplit, urlunsplit

VOID = frozenset('area base br col embed hr img input link meta param source track wbr'.split())
LANGUAGES = ('zh', 'en', 'ja', 'de')
# Only the homepage exists in these languages; their other links go to English pages and media.
HOME_ONLY = ('ja', 'de')


class Localizer(HTMLParser):
    def __init__(self, language: str, page_paths: set[str]):
        super().__init__(convert_charrefs=False)
        self.language = language
        self.page_paths = page_paths
        self.stack = []
        self.parts = []

    def handle_starttag(self, tag, attrs):
        self.start(tag, attrs, False)

    def handle_startendtag(self, tag, attrs):
        self.start(tag, attrs, True)

    def start(self, tag, attrs, closed):
        values = dict(attrs)
        language = values.get('lang', '').split('-')[0]
        hidden = bool(self.stack and self.stack[-1][1]) or (language in LANGUAGES and language != self.language)
        if not closed and tag not in VOID:
            self.stack.append((tag, hidden))
        if hidden:
            return
        if tag == 'a' and 'href' in values and not {'lang-toggle', 'lang-option'} & set(values.get('class', '').split()):
            url = urlsplit(values['href'])
            if not url.scheme and not url.netloc:
                target = self.language
                if self.language in HOME_ONLY and url.path != '/':
                    target = 'en'
                path = url.path
                if url.path in self.page_paths and target != 'zh':
                    path = '/' + target + url.path
                fragment = 'report-' + target if url.fragment == 'report' else url.fragment
                values['href'] = urlunsplit(('', '', path, url.query, fragment))
        media = self.language if self.language not in HOME_ONLY or values.get('data-src-' + self.language) \
            or values.get('data-video-' + self.language) else 'en'
        if tag == 'img' and values.get('data-src-' + media):
            values['src'] = values['data-src-' + media]
        if tag == 'video' and values.get('data-video-' + media):
            values['src'] = values['data-video-' + media]
            values['poster'] = values['data-poster-' + media]
        attributes = ''.join(' ' + key + ('' if value is None else '="' + escape(value, quote=True) + '"') for key, value in values.items())
        self.parts.append('<' + tag + attributes + (' />' if closed else '>'))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1][0] != tag:
            raise ValueError('Unbalanced source HTML at </' + tag + '>')
        _, hidden = self.stack.pop()
        if not hidden:
            self.parts.append('</' + tag + '>')

    def append(self, text):
        if not self.stack or not self.stack[-1][1]:
            self.parts.append(text)

    def handle_data(self, data):
        self.append(data)

    def handle_entityref(self, name):
        self.append('&' + name + ';')

    def handle_charref(self, name):
        self.append('&#' + name + ';')

    def handle_comment(self, data):
        self.append('<!--' + data + '-->')


def localize(content: str, language: str, page_paths: set[str]) -> str:
    parser = Localizer(language, page_paths)
    parser.feed(content)
    parser.close()
    if parser.stack:
        raise ValueError('Unclosed HTML elements: ' + str(parser.stack))
    return '\n'.join(line.rstrip() for line in ''.join(parser.parts).split('\n'))
