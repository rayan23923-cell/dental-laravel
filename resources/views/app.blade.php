@php
    // Resolved server-side and written straight onto <html> so the palette
    // is in place before the first paint — picking the theme in JavaScript
    // would flash the previous colours on every page load.
    $theme = \App\Support\ThemePalette::resolve(\App\Models\ClinicSetting::current()->theme);
@endphp
<!DOCTYPE html>
<html
    lang="{{ str_replace('_', '-', app()->getLocale()) }}"
    {{--
        Deliberately NOT setting `dir` here from the locale. This document
        has never carried a `dir` attribute at all (confirmed live —
        `AuthenticatedLayout.vue`'s ~50 pages were built and have run for
        months under the browser's implicit LTR default; only
        `print/layout.blade.php`/`privacy-policy.blade.php`/`DoctorLayout.vue`
        opt into `dir="rtl"` on their own, standalone templates). Flipping
        the *document* direction based on locale would re-flow every
        Tailwind logical-spacing utility (`ms-`/`me-`) and flex/grid
        ordering across the whole staff app at once — a real visual
        regression risk for dozens of pages this pass never reviewed.
        Arabic text still reads correctly right-to-left at the inline
        level without it (Unicode's own bidi algorithm), which is what
        every existing page already relies on. RTL as a real per-locale
        *layout* concern is future work once each page is checked, not a
        one-line default to flip today.
    --}}
    data-theme="{{ $theme }}"
    class="{{ \App\Support\ThemePalette::isDark($theme) ? 'theme-dark' : 'theme-light' }}"
    style="{{ \App\Support\ThemePalette::cssVariables($theme) }}"
>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title inertia>{{ config('app.name', 'Dental Clinic') }}</title>

        <!-- PWA: installable "Add to Home Screen" support — manifest served
             from a route (App\Http\Controllers\PwaManifestController) so its
             start_url/scope/icon URLs resolve against this install's actual
             sub-directory base path. theme-color is a fixed Instagram-brand
             value (see the manifest controller's own docblock for why), not
             the admin-configurable theme. iOS ignores the manifest's own
             icon array for home-screen icons, hence the explicit
             apple-touch-icon tag below — kept in sync with the manifest's
             own icon choice (uploaded clinic logo when one exists, else the
             same tooth-artwork fallback) rather than hardcoded separately. -->
        <link rel="manifest" href="{{ route('pwa.manifest') }}">
        <meta name="theme-color" content="#0095F6">
        <link rel="apple-touch-icon" href="{{ \App\Models\ClinicSetting::current()->logoUrl() ?: asset('icons/icon-192.png') }}">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-title" content="{{ config('app.name', 'Dental Clinic') }}">

        <!-- Fonts -->
        <link rel="preconnect" href="https://fonts.bunny.net">
        <link href="https://fonts.bunny.net/css?family=figtree:400,500,600&display=swap" rel="stylesheet" />

        <!-- Scripts -->
        @routes
        @vite(['resources/js/app.js', "resources/js/Pages/{$page['component']}.vue"])
        @inertiaHead
    </head>
    <body class="font-sans antialiased">
        @inertia

        <!-- iOS "Add to Home Screen" hint (by request, 2026-09-01) — Safari
             on iOS has no `beforeinstallprompt` equivalent at all (Apple
             never implemented it, on any iOS browser, since they all run on
             WebKit); the only path to installing is the user manually
             opening the Share sheet and tapping "Add to Home Screen"
             themselves, with no way to trigger that programmatically. This
             banner exists only to point that path out, once, dismissibly —
             it does not and cannot install anything itself. Uses the same
             theme-picker tokens (`surface`/`content`/`hairline`/`accent`,
             `tailwind.config.js`) the rest of the authenticated app uses,
             not the fixed `ig-*` tokens — unlike the PWA manifest/icons
             (a one-time OS-level identity, see PwaManifestController's own
             docblock), this banner is an ordinary in-app UI element visible
             to logged-in users on whatever theme is active, the same
             reasoning that keeps the dashboard/admin panels on the
             theme-picker instead of the fixed guest-page palette. -->
        <div
            id="ios-a2hs-hint"
            style="display:none"
            class="fixed inset-x-0 bottom-0 z-50 border-t border-hairline bg-surface px-4 py-3 shadow-panel"
        >
            <div class="mx-auto flex max-w-md items-center gap-3">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" class="shrink-0 text-accent" aria-hidden="true">
                    <path d="M12 3v12m0-12 4 4m-4-4-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                    <path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
                <p class="flex-1 text-xs leading-snug text-content">
                    ثبّت هذا التطبيق على شاشتك الرئيسية: اضغط زر
                    <strong>المشاركة</strong> بالأسفل، ثم اختر
                    <strong>"إضافة إلى الشاشة الرئيسية"</strong>.
                </p>
                <button
                    type="button"
                    id="ios-a2hs-hint-close"
                    aria-label="إغلاق"
                    class="shrink-0 rounded-full p-1 text-muted hover:bg-app-soft"
                >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                        <path d="M6 6l12 12M18 6 6 18" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
                    </svg>
                </button>
            </div>
        </div>

        <script>
            // Service-worker registration — inline (not routed through the
            // Vite bundle) so it runs unconditionally and its URL is
            // server-computed via asset(), correctly sub-directory-aware
            // without depending on Vite's own `base: './'` relative-URL
            // rewriting. See public/sw.js's own header comment for exactly
            // what it does and does not cache.
            if ('serviceWorker' in navigator) {
                window.addEventListener('load', () => {
                    navigator.serviceWorker.register('{{ asset('sw.js') }}', {
                        scope: '{{ asset('/') }}',
                    });
                });
            }

            // iOS "Add to Home Screen" hint — shown only when: (1) this is
            // Safari on iOS/iPadOS specifically (not Chrome/Firefox-on-iOS,
            // which carry their own "CriOS"/"FxiOS" UA tokens even though
            // they're WebKit underneath — the Share-sheet flow described
            // above is Safari's own UI, not necessarily identical in
            // those); (2) it isn't already running as an installed
            // standalone app (`navigator.standalone` is Safari's own
            // pre-standard flag for exactly this, still the only reliable
            // signal on iOS); (3) the user hasn't dismissed it before
            // (localStorage, permanent — this is a one-time tip, not a
            // recurring nag).
            (function () {
                var ua = navigator.userAgent;
                var isIos = /iPad|iPhone|iPod/.test(ua) ||
                    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1); // iPadOS 13+ reports as "Macintosh"
                var isSafari = /^((?!CriOS|FxiOS|EdgiOS|OPiOS).)*Safari/.test(ua);
                var isStandalone = window.navigator.standalone === true ||
                    window.matchMedia('(display-mode: standalone)').matches;
                var dismissed = localStorage.getItem('ios-a2hs-hint-dismissed') === '1';

                if (isIos && isSafari && !isStandalone && !dismissed) {
                    var el = document.getElementById('ios-a2hs-hint');
                    el.style.display = 'block';
                    document.getElementById('ios-a2hs-hint-close').addEventListener('click', function () {
                        el.style.display = 'none';
                        localStorage.setItem('ios-a2hs-hint-dismissed', '1');
                    });
                }
            })();
        </script>
    </body>
</html>
