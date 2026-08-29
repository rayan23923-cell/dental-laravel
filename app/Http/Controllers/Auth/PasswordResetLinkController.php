<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\OtpPasswordResetBroker;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "Forgot password" request step — sends a 5-minute one-time code instead
 * of a clickable link (2026-08-29, by request; see
 * App\Services\OtpPasswordResetBroker). No longer uses Laravel's `Password`
 * facade at all, so there is no `$status` string to translate/branch on;
 * the response is unconditionally neutral (see `store()`'s comment).
 */
class PasswordResetLinkController extends Controller
{
    /**
     * Display the password reset link request view.
     */
    public function create(): Response
    {
        return Inertia::render('Auth/ForgotPassword', [
            'status' => session('status'),
        ]);
    }

    /**
     * Handle an incoming password reset code request.
     */
    public function store(Request $request): RedirectResponse
    {
        $request->validate(['email' => 'required|email']);

        $user = User::where('email', $request->email)->first();
        if ($user) {
            OtpPasswordResetBroker::send($request->email, 'users', $user);
        }

        // Always the same neutral redirect regardless of whether the
        // address is registered — differentiating would let anyone probe
        // which addresses belong to a real account.
        return redirect()->route('password.reset', ['email' => $request->email])
            ->with('status', 'إذا كان هذا البريد مسجلاً لدينا، فسيصلك رمز التحقق خلال دقائق.');
    }
}
