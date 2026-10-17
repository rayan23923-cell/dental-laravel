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
 * (Sanctum tokens are stateless). Since 2026-10-17 the app keeps its own
 * choice (checked once by `POST /api/v1/academic-sessions/select`) and
 * sends it on every API request as the `X-Academic-Session` header, which
 * resolve() honours exactly like the web's stored selection. Without the
 * header every request falls through to `is_current`, unless the endpoint
 * accepts an explicit `academic_session_id` query param.
 */
class AcademicSessionHelper
{
    private const SESSION_KEY = 'academic_session_id';

    public const HEADER = 'X-Academic-Session';

    /**
     * Returns null on a fresh install with zero academic_sessions rows —
     * callers must handle that (unlike the original PHP, which would fatal
     * on a query against an empty result in the same situation; this port
     * treats "no sessions exist yet" as a valid, non-error state).
     */
    public static function resolve(): ?AcademicSession
    {
        $selectedId = static::headerSelection() ?? Session::get(self::SESSION_KEY);
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

    /** The app's choice, from an API request's header; null when absent or not a number. */
    private static function headerSelection(): ?int
    {
        if (! app()->bound('request')) {
            return null;
        }

        $request = request();
        if (! $request->is('api/*')) {
            return null;
        }

        $value = $request->header(self::HEADER);

        return is_string($value) && ctype_digit($value) ? (int) $value : null;
    }

    public static function setSelected(AcademicSession $session): void
    {
        Session::put(self::SESSION_KEY, $session->id);
    }
}
