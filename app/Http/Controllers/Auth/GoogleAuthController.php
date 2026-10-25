<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\Doctor;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Laravel\Socialite\Facades\Socialite;

/**
 * "Sign in with Google", shared by the one unified login page.
 *
 * **Sign-in only, never sign-up.** A Google account is matched to an
 * *existing* row by email — on the `users` table for staff, `doctors` for
 * doctors — and never used to create one. This system has no open
 * self-registration for either audience (doctor accounts are admin-created;
 * see DoctorController::store()), so auto-provisioning an account from
 * whoever happens to sign in with a matching Gmail address would be a
 * bypass of that, not a convenience.
 *
 * **Auto-detects staff vs. doctor from the email**, same policy as
 * `LoginRequest::authenticate()` — tries `users` first, then `doctors`.
 * There's no "which login screen did this come from" state to track
 * anymore (no separate staff/doctor login pages), so `redirect()` no
 * longer needs to stash anything before leaving for Google.
 *
 * Requires `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` (from Google Cloud
 * Console) in `.env` — see README "Sign in with Google" for the exact
 * setup steps. The login page hides the button entirely when either is
 * unset (`HandleInertiaRequests` shares `googleSignInEnabled`), so an
 * unconfigured install never shows a button that can't work.
 */
class GoogleAuthController extends Controller
{
    public function redirect(): RedirectResponse
    {
        abort_unless(config('services.google.client_id') && config('services.google.client_secret'), 404);

        return Socialite::driver('google')->redirect();
    }

    public function callback(): RedirectResponse
    {
        try {
            $googleUser = Socialite::driver('google')->user();
        } catch (\Throwable $e) {
            // Covers an expired/invalid state (the user sat on Google's
            // consent screen too long, or a repost of an old callback URL)
            // as well as the user simply clicking "Cancel" on Google's side.
            Log::warning('Google sign-in failed', ['error' => $e->getMessage()]);

            return redirect()->route('login')
                ->withErrors(['login' => 'تعذر تسجيل الدخول عبر Google. حاول مرة أخرى.']);
        }

        if (! $googleUser->getEmail()) {
            return redirect()->route('login')
                ->withErrors(['login' => 'حساب Google هذا لا يحتوي على بريد إلكتروني.']);
        }

        // A switched-off staff account can't sign in this way either (2026-10-25).
        $user = User::where('email', $googleUser->getEmail())->where('status', '!=', 'inactive')->first();

        if ($user) {
            Auth::guard('web')->login($user);

            return redirect()->intended(route('dashboard', absolute: false));
        }

        $doctor = Doctor::where('email', $googleUser->getEmail())->first();

        if ($doctor) {
            Auth::guard('doctor')->login($doctor);

            return redirect()->intended(route('doctor.dashboard', absolute: false));
        }

        return redirect()->route('login')
            ->withErrors(['login' => 'لا يوجد حساب مرتبط بهذا البريد الإلكتروني.']);
    }
}
