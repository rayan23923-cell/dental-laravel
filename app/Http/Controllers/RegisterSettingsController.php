<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Models\Task;
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
            'lab' => ClinicSetting::current()->only(['lab_fee', 'lab_validity_days', 'clinic_currency']),
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
            'day_ids' => ['array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $service = Service::create(['name' => $validated['name'], 'price' => $validated['price'] ?? null]);
        $service->days()->sync($validated['day_ids'] ?? []);

        return back()->with('success', 'تمت إضافة الخدمة.');
    }

    public function updateService(Request $request, Service $service): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('register_services', 'name')->ignore($service->id)],
            'price' => ['nullable', 'numeric', 'min:0'],
            'day_ids' => ['sometimes', 'array'],
            'day_ids.*' => ['integer', 'exists:register_days,id'],
        ]);

        $service->update(['name' => $validated['name'], 'price' => $validated['price'] ?? null]);
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
        ]);

        ClinicSetting::current()->update($validated);

        return back()->with('success', 'تم حفظ إعدادات المختبر.');
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
