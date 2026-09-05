<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Storage;

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
 *
 * The install icon itself, though, DOES follow the admin's own upload
 * (2026-09-05, by request) — the generic tooth artwork in `public/icons/`
 * only ever stood in for a real clinic identity, so once a clinic logo is
 * uploaded (`ClinicSetting::logoUrl()`) it replaces the static PNGs
 * outright rather than sitting alongside them.
 */
class PwaManifestController extends Controller
{
    public function show(): JsonResponse
    {
        $settings = ClinicSetting::current();
        $name = $settings->clinic_name ?: config('app.name', 'Dental Clinic');

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
            'icons' => $this->icons($settings),
        ])->header('Content-Type', 'application/manifest+json');
    }

    /**
     * The same uploaded image stands in for every required manifest slot
     * (both declared sizes, plus the maskable purpose) since nothing here
     * rasterizes it to each exact size on upload — browsers scale one
     * source to fit whichever slot they pick. An admin-uploaded logo isn't
     * pre-composed with the safe-zone padding a real maskable icon needs,
     * but offering it there anyway beats falling back to the tooth artwork
     * on platforms (Android's adaptive icon shape) that require a maskable
     * entry to exist at all.
     */
    private function icons(ClinicSetting $settings): array
    {
        $logoUrl = $settings->logoUrl();
        if (! $logoUrl) {
            return [
                ['src' => asset('icons/icon-192.png'), 'sizes' => '192x192', 'type' => 'image/png', 'purpose' => 'any'],
                ['src' => asset('icons/icon-512.png'), 'sizes' => '512x512', 'type' => 'image/png', 'purpose' => 'any'],
                ['src' => asset('icons/icon-512-maskable.png'), 'sizes' => '512x512', 'type' => 'image/png', 'purpose' => 'maskable'],
            ];
        }

        $type = Storage::disk('public')->mimeType($settings->clinic_logo) ?: 'image/png';

        return [
            ['src' => $logoUrl, 'sizes' => '192x192', 'type' => $type, 'purpose' => 'any'],
            ['src' => $logoUrl, 'sizes' => '512x512', 'type' => $type, 'purpose' => 'any'],
            ['src' => $logoUrl, 'sizes' => '512x512', 'type' => $type, 'purpose' => 'maskable'],
        ];
    }
}
