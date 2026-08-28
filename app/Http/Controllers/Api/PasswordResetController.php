<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Doctor;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;

/**
 * "نسيت كلمة المرور؟" for the Flutter client — mirrors
 * `Auth\DoctorPasswordResetController::email()` and Breeze's own
 * `PasswordResetLinkController` (staff), unified into one endpoint the
 * same way `AuthController::login()` unifies both account types: the
 * mobile app never asks which kind of account this is before submitting.
 *
 * Only sends the email — completing the reset (choosing a new password)
 * happens by opening the emailed link, which lands on the existing web
 * reset-password page (`doctor.password.reset`/`password.reset`). No
 * native in-app reset-token screen: that page already exists and works,
 * duplicating it here would just be a second copy to keep in sync.
 */
class PasswordResetController extends Controller
{
    public function sendResetLink(Request $request): JsonResponse
    {
        $validated = $request->validate(['email' => ['required', 'email']]);

        // Always the same neutral response regardless of which broker (or
        // neither) matched — differentiating would let anyone probe which
        // addresses belong to a registered account, same reasoning as the
        // web controller this mirrors.
        if (User::where('email', $validated['email'])->exists()) {
            Password::broker('users')->sendResetLink($validated);
        } elseif (Doctor::where('email', $validated['email'])->exists()) {
            Password::broker('doctors')->sendResetLink($validated);
        }

        return response()->json(['message' => 'إذا كان هذا البريد مسجلاً لدينا، فسيصلك رابط لإعادة تعيين كلمة المرور.']);
    }
}
