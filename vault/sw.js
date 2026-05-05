const CACHE = "sundai-v13";

const FILES = [
  "./",
  "./index.html",
  "./index.html",
  "./liquidations.html",
  "./manifest.json",
  "./sundailogo.png",
  "./icon-192.png",
  "./icon-512.png",
  "./ethers.umd.min.js",
  "./vault-abi.json",
  "./token-abi.json",
  "./oracle-abi.json"
];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(FILES))
  );
  self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  if (e.request.mode === "navigate") {
    // Strip query string so ?t=timestamp cache-busting doesn't cause misses
    const url = new URL(e.request.url);
    url.search = "";
    const cleanRequest = new Request(url.toString());
    e.respondWith(
      caches.match(cleanRequest)
        .then(r => r || fetch(e.request))
    );
    return;
  }

  e.respondWith(
    caches.match(e.request).then(resp => resp || fetch(e.request).then(netResp => {
      return caches.open(CACHE).then(cache => {
        cache.put(e.request, netResp.clone());
        return netResp;
      });
    }))
  );
});
