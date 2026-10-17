// Keeps the app itself on the phone so it opens with bad venue Wi-Fi. Data calls (/api) always go
// to the network; scouting is saved in the browser and syncs when there's a connection.
const CACHE = "frc-scout-v3";
const SHELL = ["/", "/index.html", "/app.js", "/style.css", "/field.jpg", "/icon-192.png", "/apple-touch-icon.png", "/manifest.webmanifest"];

self.addEventListener("install", (e) => e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener("activate", (e) => e.waitUntil(
  caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.pathname.startsWith("/api/")) return;
  // Network first so updates show up right away; the cached copy is the fallback offline.
  // no-cache = always ask the server (a quick "unchanged?" check), so an update shows up on the next open.
  e.respondWith(fetch(e.request, { cache: "no-cache" }).then((res) => {
    const copy = res.clone();
    caches.open(CACHE).then((c) => c.put(e.request, copy));
    return res;
  }).catch(() => caches.match(e.request)));
});
