<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicSetting;
use App\Models\User;
use App\Services\PermissionManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Storage;

/**
 * Mirrors App\Http\Controllers\ClinicSettingController for the Flutter
 * client (branding info — name/logo/contact — for an app splash/about
 * screen). See ClinicSetting model docblock for excluded fields.
 *
 * Mail (SMTP) settings (2026-10-17): editable from the app as on the web,
 * and only shown to whoever may view settings, since every signed-in
 * client reads show(). The stored password is never returned — only
 * `mail_password_set` — and a blank one on update keeps it.
 */
class ClinicSettingController extends Controller
{
    private const MAIL_FIELDS = ['mail_host', 'mail_port', 'mail_username', 'mail_encryption', 'mail_from_address', 'mail_from_name'];

    public function show(Request $request): JsonResponse
    {
        return response()->json($this->payload(ClinicSetting::current(), $request));
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
            'groups_enabled' => ['sometimes', 'boolean'],
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

        // A blank password means "keep the stored one", as on the web: the
        // app never receives the current value to send back.
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

        return response()->json($this->payload($settings->fresh(), $request));
    }

    /**
     * The web's clinic-settings.test-email: one message through the saved
     * SMTP settings, reporting the transport's own error text on failure
     * (the useful part, e.g. Gmail refusing a normal account password).
     */
    public function sendTestEmail(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'to' => ['required', 'email'],
        ]);

        $settings = ClinicSetting::current();

        if (! $settings->mailConfigured()) {
            return response()->json(['message' => 'أدخل خادم SMTP وعنوان المرسل واحفظ الإعدادات أولاً.'], 422);
        }

        try {
            Mail::raw(
                "رسالة تجريبية من {$settings->clinic_name}.\n\nإذا وصلتك هذه الرسالة فإن إعدادات SMTP تعمل بشكل صحيح.",
                fn ($message) => $message->to($validated['to'])
                    ->subject("رسالة تجريبية — {$settings->clinic_name}")
            );
        } catch (\Throwable $e) {
            Log::warning('Test email failed', ['error' => $e->getMessage()]);

            return response()->json(['message' => 'فشل الإرسال: '.$e->getMessage()], 422);
        }

        return response()->json(['message' => "تم إرسال رسالة تجريبية إلى {$validated['to']}."]);
    }

    private function payload(ClinicSetting $settings, Request $request): array
    {
        $data = [
            ...$settings->toArray(),
            'logo_url' => $settings->logoUrl(),
            'university_logo_url' => $settings->universityLogoUrl(),
        ];

        $user = $request->user();
        if ($user instanceof User && (new PermissionManager($user))->can('settings', 'view')) {
            $data['mail_password_set'] = filled($settings->mail_password);
            $data['mail_configured'] = $settings->mailConfigured();
            $data['mail_driver'] = config('mail.default');
        } else {
            foreach (self::MAIL_FIELDS as $key) {
                unset($data[$key]);
            }
        }

        return $data;
    }
}
