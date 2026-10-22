<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Public, unauthenticated reachability check for the apps' connection
 * indicator (green/red dot, 2026-10-22). Touches the database too, so a
 * running web server with a stopped database still shows as down (503).
 */
class PingController extends Controller
{
    public function __invoke(): JsonResponse
    {
        try {
            DB::select('select 1');
        } catch (\Throwable) {
            return response()->json(['ok' => false, 'database' => false], 503);
        }

        return response()->json(['ok' => true, 'database' => true, 'time' => now()->toIso8601String()])
            ->header('Cache-Control', 'no-store');
    }
}
