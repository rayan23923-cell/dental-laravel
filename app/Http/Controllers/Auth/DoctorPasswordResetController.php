<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\Doctor;
use App\Services\OtpPasswordResetBroker;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Forgot/reset password for the `doctor` guard. Breeze only ships this for
 * staff users; doctors live in their own table behind their own guard, so
 * they need their own routes.
 *
 * Neither existed in the original app at all — it has no password reset of
 * any kind (verified by grepping its whole codebase).
 *
 * Sends a 5-minute one-time code instead of a clickable link (2026-08-29,
 * by request; see App\Services\OtpPasswordResetBroker) — no longer uses
 * Laravel's `Password` facade/`doctors` broker (config/auth.php) at all,
 * so there's no `$status` string to translate/branch on.
 */
class DoctorPasswordResetController extends Controller
{
    private const GUARD = 'doctors';

    public function request(): Response
    {
        return Inertia::render('Auth/DoctorForgotPassword', [
            'status' => session('status'),
        ]);
    }

    public function email(Request $request): RedirectResponse
    {
        $request->validate(['email' => ['required', 'email']]);

        $doctor = Doctor::where('email', $request->email)->first();
        if ($doctor) {
            OtpPasswordResetBroker::send($request->email, self::GUARD, $doctor);
        }

        // Always the same neutral redirect: differentiating would let
        // anyone probe which addresses are registered doctors.
        return redirect()->route('doctor.password.reset', ['email' => $request->email])
            ->with('status', 'إذا كان هذا البريد مسجلاً لدينا، فسيصلك رمز التحقق خلال دقائق.');
    }

    public function reset(Request $request): Response
    {
        return Inertia::render('Auth/DoctorResetPassword', [
            'email' => $request->string('email')->toString(),
            'status' => session('status'),
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        $request->validate([
            'email' => ['required', 'email'],
            'otp' => ['required', 'digits:6'],
            'password' => ['required', 'confirmed', 'min:6'],
        ]);

        if (! OtpPasswordResetBroker::verify($request->email, self::GUARD, $request->otp)) {
            throw ValidationException::withMessages([
                'otp' => ['رمز التحقق غير صحيح أو منتهي الصلاحية.'],
            ]);
        }

        $doctor = Doctor::where('email', $request->email)->first();
        if (! $doctor) {
            throw ValidationException::withMessages(['email' => ['هذا البريد غير مسجل.']]);
        }

        $doctor->forceFill([
            'password' => Hash::make($request->password),
            'remember_token' => Str::random(60),
        ])->save();

        OtpPasswordResetBroker::forget($request->email, self::GUARD);

        return redirect()->route('login')->with('status', __('Your password has been reset.'));
    }
}
