<?php

namespace App\Http\Middleware;

use App\Support\OfflineLicensing;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * An offline copy is usable only once activated on this computer
 * (2026-10-17, by request); until then every page leads to /activate.
 * Does nothing on the hosted system.
 */
class EnsureOfflineActivated
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! OfflineLicensing::required() || $request->is('activate') || OfflineLicensing::current()) {
            return $next($request);
        }

        if ($request->expectsJson() || $request->is('api/*')) {
            return response()->json(['message' => 'النظام غير مفعّل على هذا الحاسوب.'], 403);
        }

        return redirect('/activate');
    }
}
