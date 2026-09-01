// Service worker for installability + fast repeat loads of static build
// assets — deliberately NOT an offline-first/app-shell cache. This is a
// clinical app (patient records, case sheets, task workflows); caching API
// responses or page HTML would risk silently showing stale clinical data,
// which is worse than showing nothing. Only Vite's hashed, content-addressed,
// immutable `/build/*` output is ever cached — everything else (every
// navigation/HTML request, `/api/*`, `storage/*`, Inertia responses) is left
// completely untouched and always goes to the network.
//
// Registered from resources/views/app.blade.php.

const CACHE_NAME = 'dental-clinic-static-v1';

self.addEventListener('install', (event) => {
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const { request } = event;

    if (request.method !== 'GET' || !request.url.includes('/build/')) {
        // No `respondWith` — falls straight through to the network,
        // exactly as if this service worker weren't here at all. This
        // covers every HTML/navigation request, every `/api/*` call, and
        // anything else not part of the hashed build output.
        return;
    }

    event.respondWith(
        caches.match(request).then((cached) => {
            if (cached) return cached;

            return fetch(request).then((response) => {
                if (response.ok) {
                    const copy = response.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
                }
                return response;
            });
        })
    );
});
