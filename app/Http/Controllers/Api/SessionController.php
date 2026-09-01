<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\SessionResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * "Active sessions" (by request, 2026-09-01: "اضف جلسات تسجيل الدخول نوع
 * الجهاز والموقع وبقية التفاصيل وعدد الاجهزة... وخروج من جميع الاجهزة كما
 * موجود في انستغرام") — every Sanctum personal access token the current
 * user holds is a "session" here (one per device/app install that's
 * logged in, matching the `device_name` already required at login). Web
 * session-cookie auth (the Inertia app's own `/login`) is a separate
 * mechanism entirely and isn't listed here — see this controller's own
 * `index()` doc comment for why that's a deliberate scope decision, not
 * an oversight.
 */
class SessionController extends Controller
{
    /**
     * Only lists Sanctum tokens (Flutter/API clients), not the web app's
     * own session-cookie login: Laravel's built-in database session
     * driver records `sessions.user_id` from the *default* guard only,
     * which is empty for a `doctor`-guard web login (this app's two
     * guards aren't both "default"), so there's no reliable way to
     * attribute a `sessions` row to "this account" the way a Sanctum
     * token's `tokenable_id` already does directly. Scoping to tokens
     * keeps this list 100% accurate rather than silently wrong for half
     * of this app's users.
     */
    public function index(Request $request): JsonResponse
    {
        $tokens = $request->user()->tokens()->orderByDesc('last_used_at')->get();

        return response()->json(['data' => SessionResource::collection($tokens)]);
    }

    /**
     * Ends one session — scoped to the authenticated user's own tokens
     * via the `tokens()` relation itself (not a bare `PersonalAccessToken::
     * find()`), so a user can never revoke another account's session by
     * guessing an id.
     */
    public function destroy(Request $request, int $id): JsonResponse
    {
        $token = $request->user()->tokens()->findOrFail($id);
        $token->delete();

        return response()->json(['message' => 'تم إنهاء الجلسة.']);
    }

    /**
     * "تسجيل الخروج من جميع الأجهزة" — matches Instagram's own "Log Out
     * of All Sessions": ends every session including the one making this
     * very request (the client is expected to also clear its own stored
     * token/navigate to login immediately after, the same as the existing
     * single-device `AuthController::logout()` already does).
     */
    public function logoutAll(Request $request): JsonResponse
    {
        $request->user()->tokens()->delete();

        return response()->json(['message' => 'تم تسجيل الخروج من جميع الأجهزة.']);
    }
}
