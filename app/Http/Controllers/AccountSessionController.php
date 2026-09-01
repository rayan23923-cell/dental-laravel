<?php

namespace App\Http\Controllers;

use App\Http\Resources\SessionResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

/**
 * Same "Active sessions" data as Api\SessionController (Sanctum tokens —
 * i.e. this account's mobile app logins), exposed here for the web Profile
 * pages instead, which authenticate via session cookie rather than a
 * bearer token. Sits behind `auth:web,doctor` in routes/web.php so either
 * guard can reach it, the same combined-guard pattern already used for the
 * case-sheet print routes.
 *
 * The web session itself is never one of the listed rows — see
 * Api\SessionController's own docblock for why web sessions aren't
 * tracked as "sessions" at all — so `is_current` is always false here;
 * this panel only ever shows *other* (mobile) devices.
 */
class AccountSessionController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $tokens = $this->account($request)->tokens()->orderByDesc('last_used_at')->get();

        return response()->json(['data' => SessionResource::collection($tokens)]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $this->account($request)->tokens()->findOrFail($id)->delete();

        return response()->json(['message' => 'تم إنهاء الجلسة.']);
    }

    public function logoutAll(Request $request): JsonResponse
    {
        $this->account($request)->tokens()->delete();

        return response()->json(['message' => 'تم تسجيل الخروج من جميع الأجهزة.']);
    }

    private function account(Request $request): \App\Models\User|\App\Models\Doctor
    {
        return Auth::guard('web')->user() ?? Auth::guard('doctor')->user();
    }
}
