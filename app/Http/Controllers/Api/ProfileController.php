<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DoctorResource;
use App\Http\Resources\UserResource;
use App\Models\Doctor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Self-profile editing for the Flutter client — mirrors
 * App\Http\Controllers\ProfileController (staff) and
 * App\Http\Controllers\Doctor\ProfileController (doctor), which the web
 * app already has as two separate session-based controllers. `GET /me`
 * (Api\AuthController::me) already tells the two account types apart via
 * `instanceof Doctor`; this controller reuses that same branch instead of
 * needing two separate route sets.
 */
class ProfileController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $account = $request->user();

        if ($account instanceof Doctor) {
            $validated = $request->validate([
                'name' => ['required', 'string', 'max:255'],
                'email' => ['required', 'email', 'max:250', Rule::unique('doctors', 'email')->ignore($account->id)],
                'phone' => ['nullable', 'string', 'max:50'],
                'profile_image' => ['nullable', 'image', 'max:2048'],
                'locale' => ['nullable', 'in:ar,en'],
            ]);

            if ($request->hasFile('profile_image')) {
                if ($account->profile_image) {
                    Storage::disk('public')->delete($account->profile_image);
                }
                $validated['profile_image'] = $request->file('profile_image')->store('doctors', 'public');
            } else {
                unset($validated['profile_image']);
            }

            $account->update($validated);

            return response()->json(new DoctorResource($account->fresh()));
        }

        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($account->id)],
            'phone' => ['nullable', 'string', 'max:50'],
            'profile_image' => ['nullable', 'image', 'max:2048'],
            'locale' => ['nullable', 'in:ar,en'],
        ]);

        if ($request->hasFile('profile_image')) {
            if ($account->profile_image) {
                Storage::disk('public')->delete($account->profile_image);
            }
            $validated['profile_image'] = $request->file('profile_image')->store('users', 'public');
        } else {
            unset($validated['profile_image']);
        }

        if ($validated['email'] !== $account->email) {
            $account->email_verified_at = null;
        }

        $account->fill($validated)->save();

        return response()->json(new UserResource($account->fresh()));
    }

    public function updatePassword(Request $request): JsonResponse
    {
        $account = $request->user();

        $validated = $request->validate([
            'old_password' => ['required', 'string'],
            'new_password' => ['required', 'string', 'min:6', 'confirmed'],
        ]);

        if (! Hash::check($validated['old_password'], $account->password)) {
            throw ValidationException::withMessages([
                'old_password' => ['كلمة المرور الحالية غير صحيحة.'],
            ]);
        }

        $account->update(['password' => Hash::make($validated['new_password'])]);

        return response()->json(['message' => 'Password updated.']);
    }
}
