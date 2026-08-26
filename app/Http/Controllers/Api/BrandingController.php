<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicSetting;
use Illuminate\Http\JsonResponse;

/**
 * Public, unauthenticated clinic branding (name + logo) — the Flutter login
 * screen needs this before any Sanctum token exists, so it can't use the
 * authenticated `Api\ClinicSettingController::show()`. Deliberately returns
 * only these two hand-picked fields rather than that controller's
 * `...$settings->toArray()` spread — `ClinicSetting` has `$hidden` secrets
 * (mail password, MikroTik credentials, JWT key) that must never be
 * reachable from a route with no auth at all, even indirectly.
 */
class BrandingController extends Controller
{
    public function __invoke(): JsonResponse
    {
        $settings = ClinicSetting::current();

        return response()->json([
            'clinic_name' => $settings->clinic_name,
            'logo_url' => $settings->logoUrl(),
        ]);
    }
}
