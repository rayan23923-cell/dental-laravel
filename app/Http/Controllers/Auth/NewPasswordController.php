<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\OtpPasswordResetBroker;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "Enter code" step — no `{token}` route parameter any more (2026-08-29,
 * by request; see App\Services\OtpPasswordResetBroker): a code is typed,
 * not clicked into, so there's nothing in the URL to carry except the
 * email the code was sent to (kept only to prefill the field, which is
 * now read-only on the client — see `ResetPassword.vue` — closing the
 * "email can be freely retyped" UI issue the request also flagged, even
 * though the backend never actually trusted that field's identity: the
 * code is looked up by whatever email is submitted, same as the old
 * token was).
 */
class NewPasswordController extends Controller
{
    /**
     * Display the password reset view.
     */
    public function create(Request $request): Response
    {
        return Inertia::render('Auth/ResetPassword', [
            'email' => $request->query('email', ''),
            'status' => session('status'),
        ]);
    }

    /**
     * Handle an incoming new password request.
     *
     * @throws ValidationException
     */
    public function store(Request $request): RedirectResponse
    {
        $request->validate([
            'email' => 'required|email',
            'otp' => ['required', 'digits:6'],
            'password' => ['required', 'confirmed', Rules\Password::defaults()],
        ]);

        if (! OtpPasswordResetBroker::verify($request->email, 'users', $request->otp)) {
            throw ValidationException::withMessages([
                'otp' => ['رمز التحقق غير صحيح أو منتهي الصلاحية.'],
            ]);
        }

        $user = User::where('email', $request->email)->first();
        if (! $user) {
            throw ValidationException::withMessages([
                'email' => [trans('passwords.user')],
            ]);
        }

        $user->forceFill([
            'password' => Hash::make($request->password),
            'remember_token' => Str::random(60),
        ])->save();

        OtpPasswordResetBroker::forget($request->email, 'users');
        event(new PasswordReset($user));

        return redirect()->route('login')->with('status', __('Your password has been reset.'));
    }
}
