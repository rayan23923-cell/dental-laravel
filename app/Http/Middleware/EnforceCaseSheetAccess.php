<?php

namespace App\Http\Middleware;

use App\Services\CaseSheetAccess;
use Closure;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Enforces the original's case-sheet access rules (see
 * App\Services\CaseSheetAccess for where each rule comes from) across all
 * specialty resources at once, rather than restating them in twelve
 * controllers where they could drift apart.
 *
 * Two rules, both from the original:
 *
 *  1. **Staff are view-only.** The original ignores their POST entirely
 *     (`if (REQUEST_METHOD === 'POST' && !$is_view_only)`) and its delete
 *     endpoint 401s without a doctor session. Any write verb from a staff
 *     principal is refused here.
 *  2. **A doctor may only touch their own record** — `$can_save_case_sheet`
 *     is `($case_owner_id === $doctor_id)`. Applies to reads too: the
 *     original's doctor queries carry `AND doctor_id = ?`, so another
 *     doctor's sheet simply doesn't load.
 *
 * Route-model binding has already run by the time route middleware
 * executes, so `$request->route('record')` is the resolved model.
 */
class EnforceCaseSheetAccess
{
    public function handle(Request $request, Closure $next): Response
    {
        $isWrite = ! $request->isMethodSafe();

        // Rule 1 — staff never write.
        if ($isWrite && CaseSheetAccess::isViewOnly()) {
            abort(403, 'Case sheets are view-only for staff; only the owning doctor can save them.');
        }

        // Rule 2 — a doctor is confined to their own records. Every bound
        // model on the route is checked rather than just `record`: the
        // operative sheet binds as {dentalChart}, so keying off one
        // parameter name would silently skip it.
        if (CaseSheetAccess::isDoctor()) {
            foreach ($request->route()?->parameters() ?? [] as $parameter) {
                if ($parameter instanceof Model && ! CaseSheetAccess::ownsRecord($parameter)) {
                    abort(403, 'This case sheet belongs to another doctor.');
                }
            }

            // Rule 3 — ownership is taken from the session, never from the
            // request. The original reads `$_SESSION['doctor_id']` and never
            // trusts a posted one; without this a doctor could file a case
            // sheet under a colleague's name simply by posting their id
            // (the form carries a doctor selector). Resources with no
            // `doctor_id` rule drop the value at validation, so this is
            // harmless for the satellite sheets.
            if ($isWrite) {
                $request->merge(['doctor_id' => CaseSheetAccess::doctor()->id]);
            }
        }

        return $next($request);
    }
}
