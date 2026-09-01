<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use Illuminate\Http\JsonResponse;

/**
 * Web-app manifest for "Add to Home Screen" / installable-PWA support.
 * Served from a route (not a static `public/manifest.json`) so `url()`
 * resolves `start_url`/`scope`/icon URLs against this install's actual
 * base path — the app is served from a sub-directory
 * (`APP_URL=http://192.168.1.155/dental_laravel/public`, see
 * `vite.config.js`'s own `base: './'` comment for the same constraint),
 * so a hand-written static file would need its URLs manually kept in
 * sync with wherever this gets deployed.
 *
 * `theme_color` is fixed Instagram blue rather than the admin-configurable
 * `App\Support\ThemePalette` — the installed app's icon/splash chrome is a
 * one-time OS-level identity, not something that should shift every time
 * an admin picks a new in-app theme, the same "one fixed, recognisable
 * look regardless of active theme" reasoning `GuestLayout.vue`'s own
 * docblock already gives for hardcoding the `ig-*` tokens on public pages.
 */
class PwaManifestController extends Controller
{
    public function show(): JsonResponse
    {
        $name = ClinicSetting::current()->clinic_name ?: config('app.name', 'Dental Clinic');

        return response()->json([
            'name' => $name,
            'short_name' => $name,
            'start_url' => url('/'),
            'scope' => url('/'),
            'id' => url('/'),
            'display' => 'standalone',
            'theme_color' => '#0095F6',
            'background_color' => '#FFFFFF',
            'lang' => 'ar',
            'icons' => [
                [
                    'src' => asset('icons/icon-192.png'),
                    'sizes' => '192x192',
                    'type' => 'image/png',
                    'purpose' => 'any',
                ],
                [
                    'src' => asset('icons/icon-512.png'),
                    'sizes' => '512x512',
                    'type' => 'image/png',
                    'purpose' => 'any',
                ],
                [
                    'src' => asset('icons/icon-512-maskable.png'),
                    'sizes' => '512x512',
                    'type' => 'image/png',
                    'purpose' => 'maskable',
                ],
            ],
        ])->header('Content-Type', 'application/manifest+json');
    }
}
