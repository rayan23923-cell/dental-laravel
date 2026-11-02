<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\AppReleases;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Public, unauthenticated version manifest the Windows desktop build polls
 * on startup (see flutter_app/lib/core/updater/desktop_update_checker.dart)
 * to silently self-update, mirroring Telegram Desktop's updater. No auth:
 * the check must succeed before a user has ever logged in.
 *
 * `/app/version?platform=android|ios` (2026-10-17) serves the phone builds
 * the same way, for the in-app updater on Android, and `android_tv`
 * (2026-11-02) the waiting-screen TV app.
 */
class DesktopReleaseController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $platform = in_array($request->query('platform'), ['android', 'ios', 'android_tv'], true) ? $request->query('platform') : 'windows';

        return response()->json(AppReleases::for($platform));
    }
}
