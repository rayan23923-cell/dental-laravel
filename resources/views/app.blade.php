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
    </body>
</html>
