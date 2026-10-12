<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Support\ThemePalette;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ports admin/clinic_settings.php. See ClinicSetting model docblock for
 * why the MikroTik fields and jwt_secret_key are excluded.
 */
class ClinicSettingController extends Controller
{
    public function edit(): Response
    {
        $settings = ClinicSetting::current();

        return Inertia::render('ClinicSettings/Edit', [
            'settings' => [
                ...$settings->toArray(),
                'logo_url' => $settings->logoUrl(),
                'university_logo_url' => $settings->universityLogoUrl(),
                // Never send the stored SMTP password to the browser — the
                // form only reports whether one is set.
                'mail_password_set' => filled($settings->mail_password),
            ],
            'mailConfigured' => $settings->mailConfigured(),
            'mailDriver' => config('mail.default'),
            'themes' => ThemePalette::forUi(),
        ]);
    }

    public function update(Request $request): RedirectResponse
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
            // Restricted to the known palettes so an unknown value can't
            // leave the app with no colour variables at all.
            'theme' => ['nullable', Rule::in(array_keys(ThemePalette::THEMES))],
            'clinic_timezone' => ['nullable', 'string', 'max:64'],
            'base_url' => ['nullable', 'string', 'max:255'],
            'university_name' => ['nullable', 'string', 'max:255'],
            'college_name' => ['nullable', 'string', 'max:255'],
            'enable_notifications' => ['boolean'],
            'enable_sms' => ['boolean'],
            'enable_email' => ['boolean'],
            'clinic_logo' => ['nullable', 'image', 'max:5120'],
            'university_logo' => ['nullable', 'image', 'max:5120'],
            'mail_host' => ['nullable', 'string', 'max:255'],
            'mail_port' => ['nullable', 'integer', 'min:1', 'max:65535'],
            'mail_username' => ['nullable', 'string', 'max:255'],
            'mail_password' => ['nullable', 'string', 'max:255'],
            'mail_encryption' => ['nullable', 'in:tls,ssl'],
            'mail_from_address' => ['nullable', 'email', 'max:255'],
            'mail_from_name' => ['nullable', 'string', 'max:255'],
        ]);

        $settings = ClinicSetting::current();

        // A blank password field means "keep the stored one" rather than
        // "clear it" — the form never receives the current value to resend.
        if (blank($validated['mail_password'] ?? null)) {
            unset($validated['mail_password']);
        }

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

        return back()->with('success', 'Clinic settings updated.');
    }

    /**
     * Sends a test message through the stored mail settings, so an SMTP
     * configuration can be verified from the UI instead of waiting for a
     * real password-reset or notification to fail silently.
     *
     * The transport's actual error text is reported back rather than
     * swallowed into a generic "failed" — with Gmail in particular that
     * text is the useful part (a plain account password is rejected with an
     * auth error, and the fix is to use an App Password instead).
     */
    public function sendTestEmail(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'to' => ['required', 'email'],
        ]);

        $settings = ClinicSetting::current();

        if (! $settings->mailConfigured()) {
            return back()->with('error', 'أدخل خادم SMTP وعنوان المرسل واحفظ الإعدادات أولاً.');
        }

        try {
            Mail::raw(
                "رسالة تجريبية من {$settings->clinic_name}.\n\nإذا وصلتك هذه الرسالة فإن إعدادات SMTP تعمل بشكل صحيح.",
                fn ($message) => $message->to($validated['to'])
                    ->subject("رسالة تجريبية — {$settings->clinic_name}")
            );
        } catch (\Throwable $e) {
            Log::warning('Test email failed', ['error' => $e->getMessage()]);

            return back()->with('error', 'فشل الإرسال: '.$e->getMessage());
        }

        return back()->with('success', "تم إرسال رسالة تجريبية إلى {$validated['to']}.");
    }
}
