<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Forgot/reset password for the `doctor` guard, using the dedicated
 * `doctors` broker (config/auth.php). Breeze only ships this for staff
 * users; doctors live in their own table behind their own guard, so they
 * need their own routes, broker and notification.
 *
 * Neither existed in the original app at all — it has no password reset of
 * any kind (verified by grepping its whole codebase).
 */
class DoctorPasswordResetController extends Controller
{
    private const BROKER = 'doctors';

    public function request(): Response
    {
        return Inertia::render('Auth/DoctorForgotPassword');
    }

    public function email(Request $request): RedirectResponse
    {
        $request->validate(['email' => ['required', 'email']]);

        $status = Password::broker(self::BROKER)->sendResetLink($request->only('email'));

        // Always report the neutral "sent" status: differentiating would
        // let anyone probe which addresses are registered doctors.
        return back()->with('status', __($status));
    }

    public function reset(Request $request, string $token): Response
    {
        return Inertia::render('Auth/DoctorResetPassword', [
            'email' => $request->string('email')->toString(),
            'token' => $token,
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        $request->validate([
            'token' => ['required'],
            'email' => ['required', 'email'],
            'password' => ['required', 'confirmed', 'min:6'],
        ]);

        $status = Password::broker(self::BROKER)->reset(
            $request->only('email', 'password', 'password_confirmation', 'token'),
            function ($doctor, string $password) {
                $doctor->forceFill([
                    'password' => Hash::make($password),
                    'remember_token' => Str::random(60),
                ])->save();
            }
        );

        if ($status !== Password::PASSWORD_RESET) {
            throw ValidationException::withMessages(['email' => [__($status)]]);
        }

        return redirect()->route('login')->with('status', __($status));
    }
}
