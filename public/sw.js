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
            Promise.all(keys.filter((key) => key !== CACHE_NAME && key !== WAITING_SCREEN_CACHE).map((key) => caches.delete(key)))
        ).then(() => self.clients.claim())
    );
});

// The one exception (2026-11-02, by request): the waiting-screen page on an
// unattended TV. Its HTML holds no patient data (the list comes from
// /api/v1/waiting-screen), so a copy is kept and served when the server
// cannot be reached; the page then keeps retrying by itself instead of the
// browser's "no connection" error that needs someone to press reload.
const WAITING_SCREEN_CACHE = 'dental-clinic-waiting-screen-v1';

self.addEventListener('fetch', (event) => {
    const { request } = event;

    if (request.method === 'GET' && request.mode === 'navigate' && new URL(request.url).pathname.endsWith('/waiting-screen')) {
        event.respondWith(
            fetch(request)
                .then((response) => {
                    if (response.ok) {
                        const copy = response.clone();
                        caches.open(WAITING_SCREEN_CACHE).then((cache) => cache.put(request, copy));
                    }
                    return response;
                })
                .catch(() => caches.open(WAITING_SCREEN_CACHE).then((cache) => cache.match(request)).then((cached) => cached || Response.error())),
        );
        return;
    }

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
