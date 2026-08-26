<?php

namespace App\Services;

use App\Models\AcademicSession;
use Illuminate\Support\Facades\Session;

/**
 * Ports the original app's includes/SessionHelper.php "which academic
 * session am I viewing" concept. Distinct from Laravel's own HTTP session —
 * this stores which academic_sessions row is currently selected, matching
 * the original's `$_SESSION['academic_session_id']`.
 *
 * Three distinct concepts, easy to conflate (kept separate here on purpose,
 * matching the original exactly):
 *  - `is_active`  — soft-enable flag (an inactive session is hidden/frozen).
 *  - `is_current` — exactly one row is the system-wide default.
 *  - "selected"   — this browser session's chosen session to view, stored
 *                    in the Laravel session, independent of `is_current`.
 *
 * The API has no browser session to persist a "selected" session in
 * (Sanctum tokens are stateless), so Api controllers call resolve() with no
 * persisted override — every request falls through to `is_current`, unless
 * the endpoint accepts an explicit `academic_session_id` query param. This
 * is a deliberate adaptation for the stateless API, not a guess: documented
 * in README.md under "Academic sessions".
 */
class AcademicSessionHelper
{
    private const SESSION_KEY = 'academic_session_id';

    /**
     * Returns null on a fresh install with zero academic_sessions rows —
     * callers must handle that (unlike the original PHP, which would fatal
     * on a query against an empty result in the same situation; this port
     * treats "no sessions exist yet" as a valid, non-error state).
     */
    public static function resolve(): ?AcademicSession
    {
        $selectedId = Session::get(self::SESSION_KEY);
        if ($selectedId) {
            $selected = AcademicSession::where('id', $selectedId)->where('is_active', true)->first();
            if ($selected) {
                return $selected;
            }
        }

        $current = AcademicSession::where('is_current', true)->where('is_active', true)->first();
        if ($current) {
            return $current;
        }

        return AcademicSession::where('is_active', true)->orderByDesc('start_date')->first();
    }

    public static function resolveId(): ?int
    {
        return static::resolve()?->id;
    }

    public static function setSelected(AcademicSession $session): void
    {
        Session::put(self::SESSION_KEY, $session->id);
    }
}
