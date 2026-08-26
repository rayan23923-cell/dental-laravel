<?php

namespace App\Http\Controllers;

use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Staff profile — rebuilt to match dental_clinics2/admin/admin_profile.php,
 * which is the same shape as the doctor one: **two forms**, `update_profile`
 * (name / email / phone / profile_image) and `change_password`
 * (old_password / new_password / confirm_password).
 *
 * Replaces the Breeze scaffold's default page, which asked only for
 * name+email — no phone and no photo, though both are real columns on
 * `users` and both appear in the original — and shipped a "delete account"
 * form the original has no equivalent of. Staff deletion belongs in user
 * management rather than self-service, so it is dropped rather than ported.
 */
class ProfileController extends Controller
{
    public function edit(Request $request): Response
    {
        $user = $request->user();

        return Inertia::render('Profile/Edit', [
            'profile' => [
                'full_name' => $user->full_name,
                'username' => $user->username,
                'email' => $user->email,
                'phone' => $user->phone,
                'role' => $user->role,
                'photo_url' => $user->profile_image ? Storage::disk('public')->url($user->profile_image) : null,
            ],
            'status' => session('status'),
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        $user = $request->user();

        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'phone' => ['nullable', 'string', 'max:50'],
            'profile_image' => ['nullable', 'image', 'max:2048'],
        ]);

        if ($request->hasFile('profile_image')) {
            if ($user->profile_image) {
                Storage::disk('public')->delete($user->profile_image);
            }
            $validated['profile_image'] = $request->file('profile_image')->store('users', 'public');
        } else {
            unset($validated['profile_image']);
        }

        // Changing the address invalidates a previous verification.
        if ($validated['email'] !== $user->email) {
            $user->email_verified_at = null;
        }

        $user->fill($validated)->save();

        return back()->with('success', 'تم تحديث الملف الشخصي.');
    }

    public function updatePassword(Request $request): RedirectResponse
    {
        $user = $request->user();

        $validated = $request->validate([
            'old_password' => ['required', 'string'],
            'new_password' => ['required', 'string', 'min:6', 'confirmed'],
        ]);

        if (! Hash::check($validated['old_password'], $user->password)) {
            throw ValidationException::withMessages([
                'old_password' => 'كلمة المرور الحالية غير صحيحة.',
            ]);
        }

        $user->update(['password' => Hash::make($validated['new_password'])]);

        return back()->with('success', 'تم تغيير كلمة المرور.');
    }
}
