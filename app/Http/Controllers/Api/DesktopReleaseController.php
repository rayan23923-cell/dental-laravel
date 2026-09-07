<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

/**
 * Public, unauthenticated version manifest the Windows desktop build polls
 * on startup (see flutter_app/lib/core/updater/desktop_update_checker.dart)
 * to silently self-update, mirroring Telegram Desktop's updater. No auth:
 * the check must succeed before a user has ever logged in.
 */
class DesktopReleaseController extends Controller
{
    public function __invoke(): JsonResponse
    {
        return response()->json(config('desktop_releases.windows'));
    }
}
