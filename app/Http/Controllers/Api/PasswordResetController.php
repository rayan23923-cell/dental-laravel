<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Doctor;
use App\Models\User;
use App\Services\OtpPasswordResetBroker;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * "نسيت كلمة المرور؟" for the Flutter client — mirrors
 * `Auth\DoctorPasswordResetController` and Breeze's own
 * `PasswordResetLinkController`/`NewPasswordController` (staff), unified
 * into one endpoint pair the same way `AuthController::login()` unifies
 * both account types: the mobile app never asks which kind of account
 * this is before submitting.
 *
 * Sends a 5-minute one-time code instead of a link (2026-08-29, by
 * request; see App\Services\OtpPasswordResetBroker) — unlike the old
 * link-based version of this controller, `reset()` below is a real,
 * native in-app completion step rather than a hand-off to a web page:
 * a typed code has nowhere else to go, whereas a clickable link could
 * always open the existing web reset-password page directly.
 */
class PasswordResetController extends Controller
{
    public function sendResetLink(Request $request): JsonResponse
    {
        $validated = $request->validate(['email' => ['required', 'email']]);

        // Always the same neutral response regardless of which guard (or
        // neither) matched — differentiating would let anyone probe which
        // addresses belong to a registered account.
        $user = User::where('email', $validated['email'])->first();
        $doctor = $user ? null : Doctor::where('email', $validated['email'])->first();

        if ($user) {
            OtpPasswordResetBroker::send($validated['email'], 'users', $user);
        } elseif ($doctor) {
            OtpPasswordResetBroker::send($validated['email'], 'doctors', $doctor);
        } else {
            // Server-side only — never reflected in the response, which
            // stays identically neutral either way (see the comment
            // above). Added 2026-08-29 alongside `OtpPasswordResetBroker`'s
            // own logging fix, purely so "no email arrived" can be told
            // apart from "this address doesn't match any account" by
            // checking storage/logs/laravel.log, without weakening the
            // anti-enumeration guarantee for anyone who can't read it.
            // `warning`, not `debug` (2026-08-30) — see
            // `OtpPasswordResetBroker::send()`'s matching comment for why:
            // production may well have `LOG_LEVEL` set above `debug`,
            // which would silently drop this (and did, on the first two
            // rounds of live testing — the log stayed empty regardless of
            // which branch actually ran).
            Log::warning('Password reset requested for unknown email', ['email' => $validated['email']]);
        }

        return response()->json(['message' => 'إذا كان هذا البريد مسجلاً لدينا، فسيصلك رمز التحقق خلال دقائق.']);
    }

    public function reset(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email'],
            'otp' => ['required', 'digits:6'],
            'password' => ['required', 'confirmed', 'min:6'],
        ]);

        $user = User::where('email', $validated['email'])->first();
        $guard = $user ? 'users' : 'doctors';
        $account = $user ?? Doctor::where('email', $validated['email'])->first();

        if (! $account || ! OtpPasswordResetBroker::verify($validated['email'], $guard, $validated['otp'])) {
            return response()->json(['message' => 'رمز التحقق غير صحيح أو منتهي الصلاحية.'], 422);
        }

        $account->forceFill([
            'password' => Hash::make($validated['password']),
            'remember_token' => Str::random(60),
        ])->save();

        OtpPasswordResetBroker::forget($validated['email'], $guard);

        return response()->json(['message' => 'تم تغيير كلمة المرور بنجاح.']);
    }
}
