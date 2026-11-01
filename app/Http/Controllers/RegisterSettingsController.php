<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Models\Task;
use App\Support\StudentDiscount;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Web port of `admin/register_settings.php` — the service-name-plus-
 * day-checkboxes config screen for the reception-desk registration
 * feature (`PatientRegistrationController`). Traditional Inertia
 * form posts, not calls into `/api/v1` — this app's Sanctum setup is
 * bearer-token-only for the Flutter client (see README "Setup"), not
 * configured for stateful same-origin cookie auth, so the web UI talks to
 * its own web routes/controller the same way every other settings screen
 * in this app already does.
 */
class RegisterSettingsController extends Controller
{
    public function edit(): Response
    {
        return Inertia::render('PatientRegistrations/Settings', [
            'days' => RegisterDay::orderBy('sort_order')->orderBy('name')->get(),
            'services' => Service::with('days:id')->orderBy('name')->get(),
            // Same query PatientRegistrationController::create() already
            // runs for the registration form's own task/diagnosis picker.
            'tasks' => Task::with('days:id')->orderBy('title')->get(['id', 'title']),
            // Lab screening price and how long a clear result stays valid
            // (2026-10-12) — also editable in clinic settings.
            'lab' => ClinicSetting::current()->only(['lab_fee', 'lab_validity_days', 'lab_student_discount_percent', 'clinic_currency']),
            // Care codes (2026-11-01, by request): on/off here, the codes on their own page.
            'supportCodes' => [
                'enabled' => \App\Support\SupportCodes::enabled(),
                'counts' => \App\Support\SupportCodes::counts(),
                'canManage' => (new \App\Services\PermissionManager(request()->user()))->can('support_codes', 'view'),
            ],
        ]);
    }

    public function storeDay(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('register_days', 'name')],
            'sort_order' => ['nullable', 'integer'],
        ]);

        RegisterDay::create($validated);

        return back()->with('success', 'تمت إضافة اليوم.');
    }

    public function destroyDay(RegisterDay $registerDay): RedirectResponse
    {
        $registerDay->delete();

        return back()->with('success', 'تم حذف اليوم.');
    }

    public function storeService(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('register_services', 'name')],
            'price' => ['nullable', 'numeric', 'min:0'],
            // Student discount percentage (2026-10-25); blank keeps the default 50.
            'student_discount_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'day_ids' => ['array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $service = Service::create([
            'name' => $validated['name'],
            'price' => $validated['price'] ?? null,
            'student_discount_percent' => $validated['student_discount_percent'] ?? StudentDiscount::DEFAULT_PERCENT,
        ]);
        $service->days()->sync($validated['day_ids'] ?? []);

        return back()->with('success', 'تمت إضافة الخدمة.');
    }

    public function updateService(Request $request, Service $service): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('register_services', 'name')->ignore($service->id)],
            'price' => ['nullable', 'numeric', 'min:0'],
            // Student discount percentage (2026-10-25); blank keeps the default 50.
            'student_discount_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'day_ids' => ['sometimes', 'array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $service->update([
            'name' => $validated['name'],
            'price' => $validated['price'] ?? null,
            'student_discount_percent' => $validated['student_discount_percent'] ?? $service->student_discount_percent,
        ]);
        if (array_key_exists('day_ids', $validated)) {
            $service->days()->sync($validated['day_ids']);
        }

        return back()->with('success', 'تم تحديث الخدمة.');
    }

    public function destroyService(Service $service): RedirectResponse
    {
        $service->delete();

        return back()->with('success', 'تم حذف الخدمة.');
    }

    public function updateLab(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'lab_fee' => ['nullable', 'numeric', 'min:0'],
            'lab_validity_days' => ['nullable', 'integer', 'min:0', 'max:3650'],
            'lab_student_discount_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
        ]);

        ClinicSetting::current()->update($validated);

        return back()->with('success', 'تم حفظ إعدادات المختبر.');
    }

    /** Care codes on/off (2026-11-01, by request). */
    public function updateSupportCodes(Request $request): RedirectResponse
    {
        $validated = $request->validate(['support_codes_enabled' => ['required', 'boolean']]);

        ClinicSetting::current()->update($validated);

        return back()->with('success', $validated['support_codes_enabled'] ? 'تم تفعيل بطاقات الرعاية.' : 'تم إلغاء تفعيل بطاقات الرعاية.');
    }

    /** See `Api\TaskRegisterDaysController::update()`'s docblock. */
    public function updateTaskDays(Request $request, Task $task): RedirectResponse
    {
        $validated = $request->validate([
            'day_ids' => ['array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $task->days()->sync($validated['day_ids'] ?? []);

        return back()->with('success', 'تم تحديث أيام التشخيص.');
    }
}
