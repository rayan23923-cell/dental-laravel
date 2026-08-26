<?php

namespace App\Http\Middleware;

use App\Models\User;
use App\Services\PermissionManager;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Usage: ->middleware('permission:doctors,delete')
 * Layered on top of (not instead of) the role: middleware — this checks
 * the granular user_permissions grant, role: checks the coarse users.role
 * enum. See README "Granular permissions" for why both exist.
 *
 * `role`/`user_permissions` are a staff-only concept (mirrors the original
 * app's `$_SESSION['role']`, which doctor sessions never had — see
 * App\Services\ScopeHelper's docblock for the same distinction). The web
 * routes this guards are already behind `auth` (the `web` guard, always a
 * User), but the API's Sanctum guard is shared with doctor tokens (see
 * routes/api.php), so a Doctor principal reaching here must be denied, not
 * passed to PermissionManager — its constructor requires a User and would
 * otherwise TypeError instead of cleanly 403ing.
 */
class EnsureUserHasPermission
{
    public function handle(Request $request, Closure $next, string $module, string $permission): Response
    {
        $user = $request->user();

        if (! $user instanceof User || ! (new PermissionManager($user))->can($module, $permission)) {
            abort(403, "You don't have permission to {$permission} {$module}.");
        }

        return $next($request);
    }
}
