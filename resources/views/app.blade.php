@php
    // Resolved server-side and written straight onto <html> so the palette
    // is in place before the first paint — picking the theme in JavaScript
    // would flash the previous colours on every page load.
    $theme = \App\Support\ThemePalette::resolve(\App\Models\ClinicSetting::current()->theme);
@endphp
<!DOCTYPE html>
<html
    lang="{{ str_replace('_', '-', app()->getLocale()) }}"
    data-theme="{{ $theme }}"
    class="{{ \App\Support\ThemePalette::isDark($theme) ? 'theme-dark' : 'theme-light' }}"
    style="{{ \App\Support\ThemePalette::cssVariables($theme) }}"
>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title inertia>{{ config('app.name', 'Laravel') }}</title>

        <!-- PWA: installable "Add to Home Screen" support — manifest served
             from a route (App\Http\Controllers\PwaManifestController) so its
             start_url/scope/icon URLs resolve against this install's actual
             sub-directory base path. theme-color/apple-touch-icon are fixed
             Instagram-brand values (see the manifest controller's own
             docblock for why), not the admin-configurable theme. iOS ignores
             the manifest's own icon array for home-screen icons, hence the
             explicit apple-touch-icon/meta tags below. -->
        <link rel="manifest" href="{{ route('pwa.manifest') }}">
        <meta name="theme-color" content="#0095F6">
        <link rel="apple-touch-icon" href="{{ asset('icons/icon-192.png') }}">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-title" content="{{ config('app.name', 'Laravel') }}">

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
        </script>
    </body>
</html>
