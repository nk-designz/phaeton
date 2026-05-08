const CACHE_NAME = "phaeton-v2";
const STATIC_ASSETS = [
  "/assets/css/app.css",
  "/assets/js/app.js",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Network-first for API and LiveView
  if (
    url.pathname.startsWith("/ngsi-ld/") ||
    url.pathname.startsWith("/live/") ||
    event.request.headers.get("upgrade") === "websocket"
  ) {
    return;
  }

  // Cache-first for static assets, but network-first for colocated hook chunks
  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(
      fetch(event.request).then((response) => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => caches.match(event.request))
    );
    return;
  }

  // Network-first for HTML pages (LiveView navigation)
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
    return;
  }
});
