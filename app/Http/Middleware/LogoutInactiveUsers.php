<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ends the web session of a staff account switched off on the users page
 * (2026-10-25, security review). Switching an account off already deletes
 * its app tokens (UserAccountAdmin::update()), but a browser that was
 * signed in kept working until its 30-day session ran out.
 */
class LogoutInactiveUsers
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = Auth::guard('web')->user();

        if ($user && $user->status === 'inactive') {
            Auth::guard('web')->logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return $request->expectsJson()
                ? response()->json(['message' => 'هذا الحساب معطّل.'], 401)
                : redirect()->route('login')->withErrors(['login' => 'هذا الحساب معطّل.']);
        }

        return $next($request);
    }
}
