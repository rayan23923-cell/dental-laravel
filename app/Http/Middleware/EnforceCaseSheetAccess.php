<?php

namespace App\Http\Middleware;

use App\Services\CaseSheetAccess;
use App\Support\CaseSheetSupervisorFields;
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
 * Three rules — the first two from the original, the third added
 * 2026-08-28 for the supervisor-preview feature:
 *
 *  1. **Staff may write only the resource's supervisor-editable fields**
 *     (`App\Support\CaseSheetSupervisorFields`) — originally "staff never
 *     write" outright (the original ignores their POST entirely), relaxed
 *     to this narrower rule so a supervisor can record their own notes/
 *     signature on an otherwise-locked sheet without gaining write access
 *     to anything the doctor filled in. A resource with no registered
 *     supervisor fields (the satellite tables this middleware also
 *     covers — surgery follow-ups/images/medications, treatment plans/
 *     materials) falls through `fieldsFor()`'s `default => []`, so staff
 *     stay exactly as fully blocked there as before.
 *  2. **A doctor may only touch their own record** — `$can_save_case_sheet`
 *     is `($case_owner_id === $doctor_id)`. Applies to reads too: the
 *     original's doctor queries carry `AND doctor_id = ?`, so another
 *     doctor's sheet simply doesn't load.
 *  3. **A doctor may never write the supervisor-editable fields** — the
 *     literal inverse of rule 1; this is what makes the split real rather
 *     than just "staff can also write these," since the doctor already
 *     owns the record and could otherwise self-sign their own supervisor
 *     approval.
 *
 * Route-model binding has already run by the time route middleware
 * executes, so `$request->route('record')` is the resolved model.
 */
class EnforceCaseSheetAccess
{
    public function handle(Request $request, Closure $next): Response
    {
        $isWrite = ! $request->isMethodSafe();
        $resource = $this->resourceFromRouteName($request->route()?->getName());
        $supervisorFields = CaseSheetSupervisorFields::fieldsFor($resource);
        $boundRecord = $this->boundRecord($request);

        // The web form (SectionedForm.vue) always submits the *whole*
        // record — every field's current value, not just what was
        // actually edited — so a payload key list alone can't tell a
        // supervisor-only edit apart from a full doctor save (every key
        // is always present either way). What actually distinguishes them
        // is which values *changed* from what's already stored, so that's
        // what rules 1 and 3 check, via `changedFields()` below — not
        // "which keys exist in the payload."
        $changedFields = $boundRecord ? $this->changedFields($request, $boundRecord) : array_keys($request->except(['_token', '_method']));

        // Rule 1 — staff may change only the supervisor fields.
        if ($isWrite && CaseSheetAccess::isViewOnly()) {
            if (array_diff($changedFields, $supervisorFields) !== []) {
                abort(403, 'Staff may only edit the supervisor notes/signature fields on a case sheet.');
            }
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

            // Rule 3 — a doctor may never *change* the supervisor fields,
            // even on their own record (resubmitting the form with a
            // supervisor's existing, unchanged notes/signature is fine —
            // only an actual edit to them is blocked).
            if ($isWrite && array_intersect($changedFields, $supervisorFields) !== []) {
                abort(403, 'The supervisor notes/signature fields can only be edited by staff.');
            }

            // Rule 4 — ownership is taken from the session, never from the
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

    /**
     * The resource slug is always `{resource}.{action}` for a web route
     * name, but `api.{resource}.{action}` on the API — every `routes/api.php`
     * route is wrapped in `Route::name('api.')->prefix('v1')->group(...)`.
     * A real bug found and fixed here (2026-08-28, caught live via a curl
     * test against this same feature before it ever reached staging): the
     * original `explode('.', $name, 2)[0]` read the leading segment
     * unconditionally, which is `'api'` — not a registered resource in
     * `CaseSheetSupervisorFields` — on every single API request. That
     * silently zeroed `$supervisorFields` on the API at all times, which
     * broke both directions of the split: staff got 403 even writing their
     * own 2 allowed fields (`array_diff($changed, [])` is never empty), and
     * a doctor could freely overwrite those same fields on their own record
     * (`array_intersect($changed, [])` is always empty, so rule 3 never
     * fired). Reading the *second-to-last* dot-segment instead of the first
     * is robust to either name shape, since the action segment (`index`/
     * `show`/`store`/`update`/`destroy`) is always exactly one segment.
     */
    private function resourceFromRouteName(?string $name): string
    {
        $segments = explode('.', $name ?? '');

        return $segments[count($segments) - 2] ?? ($segments[0] ?? '');
    }

    /** The bound Eloquent model on this route, if any (none on `store`). */
    private function boundRecord(Request $request): ?Model
    {
        foreach ($request->route()?->parameters() ?? [] as $parameter) {
            if ($parameter instanceof Model) {
                return $parameter;
            }
        }

        return null;
    }

    /**
     * Payload keys (minus framework artifacts — Inertia's own PUT-via-POST
     * method-spoofing sends `_method` on every case-sheet save, see
     * SectionedForm.vue) whose value actually differs from what's already
     * stored on `$record`. String-cast comparison deliberately, not `==`
     * — avoids PHP's numeric/loose-comparison surprises between a posted
     * string and a cast DB value for what's just a security gate, not the
     * save path itself (validation still normalizes/casts properly).
     */
    private function changedFields(Request $request, Model $record): array
    {
        $changed = [];
        foreach ($request->except(['_token', '_method']) as $key => $value) {
            if ((string) ($value ?? '') !== (string) ($record->getAttribute($key) ?? '')) {
                $changed[] = $key;
            }
        }

        return $changed;
    }
}
