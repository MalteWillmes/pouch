/* Pouch offline helper.
   Keeps a copy of the app itself so it opens without signal. Your lists are not stored here;
   the page keeps the last copy it saw and syncs changes when you're back online. */
const CACHE = 'pouch-app-v1';
const SHELL = ['./', 'categories.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png'];
const CDN = /(^|\.)(cdn\.jsdelivr\.net|fonts\.googleapis\.com|fonts\.gstatic\.com)$/;

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.pathname.endsWith('/version.txt')) return;            // update checks always ask the server
  const same = url.origin === self.location.origin;

  // The page and our own files: newest from the network, the saved copy when offline
  if (req.mode === 'navigate' || same) {
    const key = req.mode === 'navigate' ? './' : url.pathname;
    e.respondWith(
      fetch(req).then(r => {
        if (r.ok) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(key, copy)); }
        return r;
      }).catch(() => caches.match(key).then(hit => hit || caches.match(req, { ignoreSearch: true })))
    );
    return;
  }
  // Libraries and fonts (their addresses never change): saved copy first
  if (CDN.test(url.hostname)) {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
      if (r.ok || r.type === 'opaque') { const copy = r.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
      return r;
    })));
  }
  // Everything else (the database) goes straight to the network
});
