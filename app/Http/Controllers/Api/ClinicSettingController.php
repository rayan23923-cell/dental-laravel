<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * Mirrors App\Http\Controllers\ClinicSettingController for the Flutter
 * client (branding info — name/logo/contact — for an app splash/about
 * screen). See ClinicSetting model docblock for excluded fields.
 */
class ClinicSettingController extends Controller
{
    public function show(): JsonResponse
    {
        $settings = ClinicSetting::current();

        return response()->json([
            ...$settings->toArray(),
            'logo_url' => $settings->logoUrl(),
            'university_logo_url' => $settings->universityLogoUrl(),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'clinic_name' => ['required', 'string', 'max:255'],
            'clinic_description' => ['nullable', 'string'],
            'clinic_address' => ['nullable', 'string'],
            'clinic_phone' => ['nullable', 'string', 'max:50'],
            'clinic_email' => ['nullable', 'email', 'max:255'],
            'clinic_website' => ['nullable', 'url', 'max:255'],
            'clinic_working_hours' => ['nullable', 'string'],
            'clinic_currency' => ['nullable', 'string', 'max:50'],
            'lab_fee' => ['nullable', 'numeric', 'min:0'],
            'lab_validity_days' => ['nullable', 'integer', 'min:0', 'max:3650'],
            'clinic_timezone' => ['nullable', 'string', 'max:64'],
            'base_url' => ['nullable', 'string', 'max:255'],
            'university_name' => ['nullable', 'string', 'max:255'],
            'college_name' => ['nullable', 'string', 'max:255'],
            'enable_notifications' => ['boolean'],
            'enable_sms' => ['boolean'],
            'enable_email' => ['boolean'],
            'clinic_logo' => ['nullable', 'image', 'max:5120'],
            'university_logo' => ['nullable', 'image', 'max:5120'],
        ]);

        $settings = ClinicSetting::current();

        if ($request->hasFile('clinic_logo')) {
            if ($settings->clinic_logo) {
                Storage::disk('public')->delete($settings->clinic_logo);
            }
            $validated['clinic_logo'] = $request->file('clinic_logo')->store('clinic', 'public');
        }

        if ($request->hasFile('university_logo')) {
            if ($settings->university_logo) {
                Storage::disk('public')->delete($settings->university_logo);
            }
            $validated['university_logo'] = $request->file('university_logo')->store('clinic', 'public');
        }

        $settings->update($validated);

        return response()->json([
            ...$settings->fresh()->toArray(),
            'logo_url' => $settings->logoUrl(),
            'university_logo_url' => $settings->universityLogoUrl(),
        ]);
    }
}
