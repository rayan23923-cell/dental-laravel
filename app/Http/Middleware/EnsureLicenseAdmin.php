<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/** Licensing portal pages need a portal account (the `license` guard), not a clinic one. */
class EnsureLicenseAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! Auth::guard('license')->check()) {
            return redirect()->guest(route('licensing.login'));
        }

        return $next($request);
    }
}
