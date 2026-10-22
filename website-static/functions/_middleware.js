// Canonical host: every other hostname bound to this project (the former
// glance.mcreator.ai and www) redirects to glancepreview.com, keeping the path
// and query. Pages `_redirects` cannot match on hostname, so this runs first.
const CANONICAL = 'glancepreview.com';

export async function onRequest({ request, next }) {
  const url = new URL(request.url);
  if (url.hostname !== CANONICAL && !url.hostname.endsWith('.pages.dev')) {
    url.hostname = CANONICAL;
    url.protocol = 'https:';
    return Response.redirect(url.toString(), 301);
  }
  return next();
}
