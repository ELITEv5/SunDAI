// sw.js — FIXED version (handles navigation fallback so installed app never 404s)
const CACHE = "sundai-v8";                  // bump version so it updates instantly

const FILES = [
  "./",                                      // ← crucial
  "index.html",
  "manifest.json",
  "sundailogo.png",
  "icon-192.png",
  "icon-512.png",
  "ethers.umd.min.js",
  "vault-abi.json",
  "token-abi.json",
  "oracle-abi.json"
];

self.addEventListener("install", e => {
  e.waitUntil(
   caches.open(CACHE).then(cache => cache.addAll(FILES))
 );
 self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(self.clients.claim());         // take control immediately
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);

  // If it’s a navigation request (user opening/refreshing the app), always return index.html
  if (e.request.mode === "navigate") {
    e.respondWith(caches.match("index.html").then(r => r || fetch(e.request)));
    return;
  }

  // Normal cache-first behaviour for all other files (images, json, js, etc.)
  e.respondWith(
    caches.match(e.request).then(resp => resp || fetch(e.request).then(netResp => {
      // optionally cache new files on the fly
      return caches.open(CACHE).then(cache => {
        cache.put(e.request, netResp.clone());
        return netResp;
      });
    }))
  );
});
