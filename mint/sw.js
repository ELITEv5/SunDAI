const CACHE = "sundai-v9";

const FILES = [
  "./",
  "./index.html",
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
  e.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);

  if (e.request.mode === "navigate") {
    e.respondWith(caches.match("./index.html").then(r => r || fetch(e.request)));
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
