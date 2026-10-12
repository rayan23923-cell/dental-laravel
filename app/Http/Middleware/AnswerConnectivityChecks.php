<?php

namespace App\Http\Middleware;

use App\Http\Controllers\CaptivePortalController;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * A device's "is there internet?" check (any path on one of the check
 * host names, sent here by the offline DNS) is answered before routing.
 * See CaptivePortalController.
 */
class AnswerConnectivityChecks
{
    public function handle(Request $request, Closure $next): Response
    {
        if (in_array(strtolower($request->getHost()), CaptivePortalController::HOSTS, true)) {
            return app(CaptivePortalController::class)->check($request);
        }

        return $next($request);
    }
}
