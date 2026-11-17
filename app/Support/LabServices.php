<?php

namespace App\Support;

use App\Models\LabService;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\User;
use App\Services\ActivityLogger;
use App\Services\PermissionManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The lab's own services and test-only patients (2026-11-17, by request),
 * shared by the web lab page and the app's `/api/lab/...` routes.
 *
 * - `lab_services.view`: see the services.
 * - `lab_services.manage`: add, rename, price, switch off, delete.
 * - `lab_services.register`: register a patient who came for the test only.
 *
 * Such a patient is an ordinary `patients_simple` row with
 * `lab_service_id` set and no reception service: the lab list shows them,
 * the reception list does not (App\Support\RegistrationArchive), and the
 * service's price is their lab fee (App\Support\StudentDiscount::labFee),
 * booked as a lab payment («مدفوعات المختبر»).
 */
class LabServices
{
    /** Active services first, for the registration form and the lists. */
    public static function list(bool $activeOnly = false): array
    {
        return LabService::query()
            ->when($activeOnly, fn ($q) => $q->where('active', true))
            ->withCount('registrations')
            ->ordered()
            ->get()
            ->map->toListArray()
            ->all();
    }

    /** What the account may do with lab services. */
    public static function abilities(PermissionManager $permissions): array
    {
        $manage = $permissions->can('lab_services', 'manage');
        $register = $permissions->can('lab_services', 'register');

        return [
            'view' => $manage || $register || $permissions->can('lab_services', 'view'),
            'manage' => $manage,
            'register' => $register,
        ];
    }

    public static function authorize(User $user, string $ability): void
    {
        abort_unless(self::abilities(new PermissionManager($user))[$ability] ?? false, 403, 'لا تملك صلاحية لهذا الإجراء.');
    }

    public static function save(Request $request, ?LabService $service = null): LabService
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('lab_services', 'name')->ignore($service?->id)],
            'price' => ['required', 'numeric', 'min:0', 'max:100000000'],
            'active' => ['sometimes', 'boolean'],
        ], [
            'name.unique' => 'توجد خدمة مختبر بهذا الاسم.',
        ]);
        $validated['name'] = trim($validated['name']);

        if ($service) {
            $service->update($validated);
            ActivityLogger::log('update', 'lab_services', "تعديل خدمة المختبر \"{$service->name}\"", $service->id, $service->only(['name', 'price', 'active']));

            return $service;
        }

        $service = LabService::create($validated + [
            'active' => true,
            'sort' => (int) LabService::max('sort') + 1,
            'created_by' => $request->user()?->id,
        ]);
        ActivityLogger::log('create', 'lab_services', "إضافة خدمة المختبر \"{$service->name}\"", $service->id, $service->only(['name', 'price']));

        return $service;
    }

    /**
     * Deletes a service no patient was registered for; one with patients
     * is switched off instead, so their records keep its name and price.
     * Returns true when it was deleted.
     */
    public static function delete(LabService $service): bool
    {
        if ($service->registrations()->withTrashed()->exists()) {
            $service->update(['active' => false]);
            ActivityLogger::log('update', 'lab_services', "إيقاف خدمة المختبر \"{$service->name}\"", $service->id);

            return false;
        }

        ActivityLogger::log('delete', 'lab_services', "حذف خدمة المختبر \"{$service->name}\"", $service->id);
        $service->delete();

        return true;
    }

    /**
     * Registers a test-only patient. With `paid` the price is booked as a
     * lab payment straight away; otherwise it is taken with the result,
     * like any lab fee (App\Support\LabFeeGate::chargeIfDue()).
     *
     * @return array{0: PatientRegistration, 1: ?Payment}
     */
    public static function register(Request $request): array
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['required', 'string', 'max:20'],
            'age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'sex' => ['nullable', 'string', 'max:20'],
            'lab_service_id' => ['required', 'integer', Rule::exists('lab_services', 'id')->where('active', true)],
            'paid' => ['sometimes', 'boolean'],
        ], [
            'lab_service_id.required' => 'اختر خدمة المختبر.',
            'lab_service_id.exists' => 'خدمة المختبر غير موجودة أو متوقفة.',
        ]);

        return DB::transaction(function () use ($validated) {
            $registration = PatientRegistration::create([
                'name' => trim($validated['name']),
                'phone' => trim($validated['phone']),
                'age' => $validated['age'] ?? null,
                'sex' => $validated['sex'] ?? null,
                'lab_service_id' => $validated['lab_service_id'],
                'screening_status' => 'pending',
                'discount_eligible' => false,
            ]);

            $payment = ($validated['paid'] ?? false)
                ? LabFeeGate::chargeIfDue($registration)
                : null;

            ActivityLogger::log('create', 'lab_services', "تسجيل مريض للفحص فقط \"{$registration->name}\"", $registration->id, [
                'lab_service_id' => $registration->lab_service_id,
                'paid' => $payment?->amount !== null ? (float) $payment->amount : null,
            ]);

            return [$registration, $payment];
        });
    }
}
