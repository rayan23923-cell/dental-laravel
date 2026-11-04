<?php

namespace App\Support;

use App\Models\CasePatientLink;
use App\Models\Doctor;
use App\Models\PatientRegistration;
use App\Models\Task;
use App\Models\TaskInstance;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * "ربط المريض بالنموذج" (2026-11-04, by request): the doctor brings a
 * patient into a case sheet by scanning the ticket/receipt QR or typing
 * the 6-digit code printed under it (for whoever can't open the camera).
 *
 * - The lab result is checked: not tested yet or «غير سليم» can't start.
 * - One registration goes to one case only, so a receipt can't be used
 *   for more than one patient (unique `patient_registration_id`).
 * - The link is kept per case: the doctor's draft for a task (doctor +
 *   task) until the task starts, then the started task instance.
 * - `patient_link_required` (general settings) makes it required before
 *   a new case sheet is saved; optional by default.
 * - Payments by department follow the linked task's department
 *   ({@see departmentTotals()}).
 */
class CasePatientLinks
{
    public const CODE_LENGTH = 6;

    /**
     * The registration a scanned QR payload or a typed code points to.
     *
     * @throws ValidationException
     */
    public static function resolve(?string $payload, ?string $code): PatientRegistration
    {
        $code = $code !== null ? preg_replace('/\D/', '', self::latinDigits($code)) : null;

        if ($code !== null && $code !== '') {
            $registration = PatientRegistration::with(['service', 'registerDay'])->where('patient_code', $code)->first();
            if (! $registration) {
                self::fail('الرمز غير صحيح، تأكد من الرقم المطبوع تحت الكيوار.');
            }

            return $registration;
        }

        $decoded = json_decode((string) $payload, true);
        if (! is_array($decoded) || ($decoded['type'] ?? null) !== 'patient_registration' || empty($decoded['id'])) {
            self::fail('رمز غير صالح — هذا ليس رمز تسجيل مريض.');
        }
        $registration = PatientRegistration::with(['service', 'registerDay'])->find($decoded['id']);
        if (! $registration) {
            self::fail('التسجيل غير موجود.');
        }

        return $registration;
    }

    /**
     * Refuses a patient who isn't tested clear yet, or whose receipt
     * already went to another case.
     *
     * @throws ValidationException
     */
    public static function ensureUsable(PatientRegistration $registration, ?int $doctorId, ?int $taskId, ?int $taskInstanceId): void
    {
        if ($registration->trashed()) {
            self::fail('هذا التسجيل مؤرشف ولا يمكن استخدامه.');
        }
        if ($registration->screening_status === 'flagged') {
            self::fail('المريض غير سليم حسب فحص المختبر، لا يمكن البدء بالمهمة.');
        }
        if ($registration->screening_status !== 'clear') {
            self::fail('لم تظهر نتيجة فحص المختبر لهذا المريض بعد، لا يمكن البدء بالمهمة.');
        }

        $link = CasePatientLink::with(['doctor:id,name', 'task:id,title'])->where('patient_registration_id', $registration->id)->first();
        if ($link && ! self::sameCase($link, $doctorId, $taskId, $taskInstanceId)) {
            $where = trim(($link->task?->title ? "«{$link->task->title}»" : '').($link->doctor?->name ? " لدى {$link->doctor->name}" : ''));
            self::fail('هذا الوصل مستخدم مسبقاً لمريض في نموذج آخر'.($where !== '' ? " ({$where})" : '').'، ولا يمكن استخدامه مرة ثانية.');
        }
    }

    /**
     * Links $registration to this case, replacing whichever patient the
     * case had before (a wrong scan can be redone).
     *
     * @throws ValidationException
     */
    public static function link(PatientRegistration $registration, Doctor $doctor, ?int $taskId, ?int $taskInstanceId, string $method): CasePatientLink
    {
        $instance = $taskInstanceId ? TaskInstance::find($taskInstanceId) : null;
        if ($taskInstanceId && (! $instance || (int) $instance->doctor_id !== (int) $doctor->id)) {
            self::fail('هذه الحالة ليست لك.');
        }
        $taskId = $instance?->task_id ?? $taskId;
        $task = $taskId ? Task::withTrashed()->find($taskId) : null;
        if (! $task) {
            self::fail('افتح النموذج من المهمة لربط المريض به.');
        }

        self::ensureUsable($registration, $doctor->id, $task->id, $instance?->id);

        return DB::transaction(function () use ($registration, $doctor, $task, $instance, $method) {
            self::caseQuery($doctor->id, $task->id, $instance?->id)
                ->where('patient_registration_id', '!=', $registration->id)
                ->delete();

            $link = CasePatientLink::updateOrCreate(
                ['patient_registration_id' => $registration->id],
                [
                    'doctor_id' => $doctor->id,
                    'task_id' => $task->id,
                    'task_instance_id' => $instance?->id,
                    'department_id' => $task->department_id,
                    'method' => $method === 'code' ? 'code' : 'qr',
                ],
            );

            if ($instance) {
                $instance->forceFill(['patient_registration_id' => $registration->id])->save();
            }

            return $link;
        });
    }

    /**
     * The doctor's "مسح رمز المريض" / "إدخال الرمز" in a case sheet: the
     * registration, checked, and linked to the case the sheet is for
     * (no case given = fill the patient's details only).
     *
     * @return array{0: PatientRegistration, 1: CasePatientLink|null}
     *
     * @throws ValidationException
     */
    public static function scanForDoctor(\Illuminate\Http\Request $request, Doctor $doctor): array
    {
        $validated = $request->validate([
            'payload' => ['nullable', 'string', 'max:2000', 'required_without:code'],
            'code' => ['nullable', 'string', 'max:20'],
            'task_id' => ['nullable', 'integer'],
            'task_instances_id' => ['nullable', 'integer'],
        ]);
        $code = $validated['code'] ?? null;
        $registration = self::resolve($validated['payload'] ?? null, $code);
        $taskId = $validated['task_id'] ?? null;
        $instanceId = $validated['task_instances_id'] ?? null;

        if (! $taskId && ! $instanceId) {
            self::ensureUsable($registration, $doctor->id, null, null);

            return [$registration, null];
        }

        return [$registration, self::link($registration, $doctor, $taskId, $instanceId, filled($code) ? 'code' : 'qr')];
    }

    /** The patient linked to this case, if any. */
    public static function forCase(?int $doctorId, ?int $taskId, ?int $taskInstanceId): ?CasePatientLink
    {
        if (! $taskInstanceId && ! ($doctorId && $taskId)) {
            return null;
        }

        return self::caseQuery($doctorId, $taskId, $taskInstanceId)->with('registration')->first();
    }

    /**
     * A supervisor started the task with the patient's QR (TaskStarter):
     * the same one-receipt-one-case rule, and the link is recorded.
     *
     * @throws ValidationException
     */
    public static function linkStartedInstance(TaskInstance $instance, PatientRegistration $registration): void
    {
        $instance->loadMissing('task');
        self::caseQuery($instance->doctor_id, $instance->task_id, null)
            ->where('patient_registration_id', '!=', $registration->id)
            ->delete();
        CasePatientLink::updateOrCreate(
            ['patient_registration_id' => $registration->id],
            [
                'doctor_id' => $instance->doctor_id,
                'task_id' => $instance->task_id,
                'task_instance_id' => $instance->id,
                'department_id' => $instance->task?->department_id,
                'method' => 'qr',
            ],
        );
    }

    /** The doctor's draft became a started task: its patient goes with it. */
    public static function moveDraftToInstance(TaskInstance $instance): void
    {
        $link = self::caseQuery($instance->doctor_id, $instance->task_id, null)->first();
        if (! $link) {
            return;
        }
        $link->update(['task_instance_id' => $instance->id]);
        if (! $instance->patient_registration_id) {
            $instance->forceFill(['patient_registration_id' => $link->patient_registration_id])->save();
        }
    }

    /** A cancelled start: the patient stays with the doctor's draft. */
    public static function detachInstance(TaskInstance $instance): void
    {
        CasePatientLink::where('task_instance_id', $instance->id)->update(['task_instance_id' => null]);
    }

    /**
     * Saving a new case sheet when linking is required: the case must
     * have a patient. Only a doctor's own sheet for a task is checked.
     *
     * @throws ValidationException
     */
    public static function enforceOnCreate(array $data): void
    {
        if (! FormSettings::get()['patient_link_required']) {
            return;
        }
        $doctorId = isset($data['doctor_id']) ? (int) $data['doctor_id'] : null;
        $instanceId = ! empty($data['task_instances_id']) ? (int) $data['task_instances_id'] : null;
        $taskId = ! empty($data['task_id']) ? (int) $data['task_id'] : null;
        if (! $instanceId && ! $taskId) {
            return;
        }
        if ($instanceId) {
            $instance = TaskInstance::find($instanceId);
            if ($instance?->patient_registration_id) {
                return;
            }
        }
        if (! self::forCase($doctorId, $taskId, $instanceId)) {
            throw ValidationException::withMessages([
                'patient_link' => 'اربط المريض بالنموذج أولاً: امسح كيوار الوصل أو اكتب الرمز المطبوع تحته.',
            ]);
        }
    }

    /** What the clients show for a linked patient. */
    public static function toView(?CasePatientLink $link): ?array
    {
        $registration = $link?->registration;
        if (! $registration) {
            return null;
        }

        return [
            'id' => $registration->id,
            'name' => $registration->name,
            'patient_code' => $registration->patient_code,
            'method' => $link->method,
            'linked_at' => $link->updated_at?->toIso8601String(),
        ];
    }

    /**
     * Payments by department (2026-11-04, by request): each payment goes
     * to the department of the case its patient was linked to. Lab fees
     * are their own row; payments of patients not linked to any case are
     * "غير مرتبط بنموذج".
     *
     * @param  \Illuminate\Database\Eloquent\Builder|\Illuminate\Database\Query\Builder  $payments  already scoped and filtered
     * @return array<int, array{key: string, department_id: int|null, name: string, count: int, total: float}>
     */
    public static function departmentTotals($payments): array
    {
        $rows = (clone $payments)->toBase()->reorder()
            ->select(['payments.type', 'payments.amount', 'payments.patient_registration_id'])
            ->get();

        $registrationIds = $rows->pluck('patient_registration_id')->filter()->unique()->values();
        $departmentOf = [];
        foreach ($registrationIds->chunk(1000) as $chunk) {
            $departmentOf += CasePatientLink::whereIn('patient_registration_id', $chunk->all())
                ->whereNotNull('department_id')
                ->pluck('department_id', 'patient_registration_id')->all();
        }
        $names = \App\Models\Department::withTrashed()->whereIn('id', array_unique(array_values($departmentOf)))->pluck('name', 'id');

        $out = [];
        foreach ($rows as $row) {
            $departmentId = $row->patient_registration_id ? ($departmentOf[$row->patient_registration_id] ?? null) : null;
            [$key, $name] = match (true) {
                $row->type === \App\Models\Payment::TYPE_LAB => ['lab', 'المختبر'],
                $departmentId === null => ['unlinked', 'غير مرتبط بنموذج'],
                default => ['department:'.$departmentId, $names[$departmentId] ?? 'قسم محذوف'],
            };
            $out[$key] ??= [
                'key' => $key,
                'department_id' => str_starts_with($key, 'department:') ? (int) $departmentId : null,
                'name' => $name,
                'count' => 0,
                'total' => 0.0,
            ];
            $out[$key]['count']++;
            $out[$key]['total'] += (float) $row->amount;
        }

        // Departments by income, then the lab, then the unlinked.
        $order = fn ($row) => match ($row['key']) {
            'lab' => 1,
            'unlinked' => 2,
            default => 0,
        };
        usort($out, fn ($a, $b) => [$order($a), -$a['total']] <=> [$order($b), -$b['total']]);

        return array_values($out);
    }

    private static function caseQuery(?int $doctorId, ?int $taskId, ?int $taskInstanceId)
    {
        return $taskInstanceId
            ? CasePatientLink::where('task_instance_id', $taskInstanceId)
            : CasePatientLink::where('doctor_id', $doctorId)->where('task_id', $taskId)->whereNull('task_instance_id');
    }

    private static function sameCase(CasePatientLink $link, ?int $doctorId, ?int $taskId, ?int $taskInstanceId): bool
    {
        if ($taskInstanceId) {
            return (int) $link->task_instance_id === $taskInstanceId;
        }

        return $link->task_instance_id === null && (int) $link->doctor_id === (int) $doctorId && (int) $link->task_id === (int) $taskId;
    }

    private static function latinDigits(string $value): string
    {
        return strtr($value, ['٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9']);
    }

    /** @throws ValidationException */
    private static function fail(string $message): never
    {
        throw ValidationException::withMessages(['patient' => $message]);
    }
}
