// Canonical host: every other hostname bound to this project (the former
// glance.mcreator.ai and www) redirects to glancepreview.com, keeping the path
// and query. Pages `_redirects` cannot match on hostname, so this runs first.
const CANONICAL = 'glancepreview.com';
const LANGUAGE_COOKIE = 'glance.language';
const SUPPORTED_LANGUAGES = new Set(['zh', 'en', 'ja', 'de']);
const COUNTRY_LANGUAGES = Object.assign(Object.create(null), {
  CN: 'zh', HK: 'zh', MO: 'zh', TW: 'zh',
  JP: 'ja',
  DE: 'de', AT: 'de', CH: 'de', LI: 'de',
});

function savedLanguage(request) {
  const cookies = (request.headers.get('Cookie') || '').split(';');
  for (const cookie of cookies) {
    const [name, ...value] = cookie.trim().split('=');
    if (name === LANGUAGE_COOKIE && SUPPORTED_LANGUAGES.has(value.join('='))) {
      return value.join('=');
    }
  }
  return null;
}

function isSearchCrawler(request) {
  return request.cf?.botManagement?.verifiedBot === true ||
    /Googlebot|bingbot|DuckDuckBot|Baiduspider|YandexBot|Applebot/i.test(request.headers.get('User-Agent') || '');
}

function privateHeaders(headers) {
  headers.set('Cache-Control', 'private, no-store');
  const vary = new Set((headers.get('Vary') || '').split(',').map(s => s.trim()).filter(Boolean));
  if (![...vary].some(s => s.toLowerCase() === 'cookie')) vary.add('Cookie');
  headers.set('Vary', [...vary].join(', '));
}

export async function onRequest({ request, next }) {
  const url = new URL(request.url);
  if (url.hostname !== CANONICAL && !url.hostname.endsWith('.pages.dev')) {
    url.hostname = CANONICAL;
    url.protocol = 'https:';
    return Response.redirect(url.toString(), 301);
  }
  // Only the language-neutral entry point is negotiated. Explicit language
  // URLs, downloads, payment callbacks, assets and deep links retain their URL.
  // Cloudflare derives cf.country from the visitor IP; no IP lookup service or
  // raw IP storage is needed. Unknown/unsupported locations fall back to English.
  const negotiate = url.pathname === '/' && ['GET', 'HEAD'].includes(request.method) && !isSearchCrawler(request);
  const preview = url.hostname.endsWith('.pages.dev');
  if (negotiate) {
    const language = savedLanguage(request) || COUNTRY_LANGUAGES[request.cf?.country] || 'en';
    if (language !== 'zh') {
      url.pathname = '/' + language + '/';
      const headers = new Headers({ Location: url.toString() });
      privateHeaders(headers);
      if (preview) headers.set('X-Robots-Tag', 'noindex');
      return new Response(null, { status: 302, headers });
    }
  }
  const response = await next();
  if (preview || negotiate) {
    const headers = new Headers(response.headers);
    if (preview) headers.set('X-Robots-Tag', 'noindex');
    if (negotiate) privateHeaders(headers);
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  }
  return response;
}
