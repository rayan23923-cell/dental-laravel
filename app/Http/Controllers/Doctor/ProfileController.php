<?php

namespace App\Http\Controllers\Doctor;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Doctor profile — port of dental_clinics2/doctor/profile.php, which has
 * **two separate forms**: `update_profile` (name/email/phone/profile_image)
 * and `change_password` (old_password/new_password/confirm_password).
 *
 * The earlier port merged them into one form with a bare optional password
 * field and **no current-password check** — anyone with a live session
 * could change the password without knowing the old one. Split and
 * verified here, matching the original.
 */
class ProfileController extends Controller
{
    public function edit(): Response
    {
        $doctor = Auth::guard('doctor')->user();
        $doctor->load('stage.educationType');

        return Inertia::render('Doctor/Profile', [
            'profile' => [
                'name' => $doctor->name,
                'username' => $doctor->username,
                'email' => $doctor->email,
                'phone' => $doctor->phone,
                'photo_url' => $doctor->profile_image ? Storage::disk('public')->url($doctor->profile_image) : null,
                'stage' => $doctor->stage?->name,
                'education_type' => $doctor->stage?->educationType?->name,
            ],
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:250', Rule::unique('doctors', 'email')->ignore($doctor->id)],
            'phone' => ['nullable', 'string', 'max:50'],
            'profile_image' => ['nullable', 'image', 'max:2048'],
        ]);

        if ($request->hasFile('profile_image')) {
            if ($doctor->profile_image) {
                Storage::disk('public')->delete($doctor->profile_image);
            }
            $validated['profile_image'] = $request->file('profile_image')->store('doctors', 'public');
        } else {
            unset($validated['profile_image']);
        }

        $doctor->update($validated);

        return back()->with('success', 'تم تحديث الملف الشخصي.');
    }

    public function updatePassword(Request $request): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();

        $validated = $request->validate([
            'old_password' => ['required', 'string'],
            'new_password' => ['required', 'string', 'min:6', 'confirmed'],
        ]);

        // The original verifies the old password before allowing a change.
        if (! Hash::check($validated['old_password'], $doctor->password)) {
            throw ValidationException::withMessages([
                'old_password' => 'كلمة المرور الحالية غير صحيحة.',
            ]);
        }

        $doctor->update(['password' => Hash::make($validated['new_password'])]);

        return back()->with('success', 'تم تغيير كلمة المرور.');
    }
}
