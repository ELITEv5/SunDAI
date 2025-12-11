// sw.js
const CACHE = "sundai-v6";

const FILES = [
  "./",
  "index.html",
  "manifest.json",
  "sundailogo.png",
  "ethers.umd.min.js",
  "vault-abi.json",
  "token-abi.json",
  "oracle-abi.json",
  "icon-192.png",
  "icon-512.png"
];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(FILES))
  );
  self.skipWaiting();
});

self.addEventListener("fetch", e => {
  e.respondWith(
    caches.match(e.request).then(resp => resp || fetch(e.request))
  );
});
