<?php

namespace App\Services;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Support\CaseCode;

/**
 * What a supervisor's scanned QR or typed case code (2026-10-30) points
 * at, for the task progress scanner on the web and the app's "case by
 * code" screen. Moved here from `TaskProgressController::scan()` so both
 * share one answer.
 *
 * A case (`task_instance`) or a task not started yet (`pending_task`) also
 * carries `card`: the same slot card the task progress matrix shows
 * (`TaskProgressGroupSummary::buildDoctorRow()`), so the same start /
 * complete / steps / edit actions work on it straight from the code.
 */
class TaskCodeLookup
{
    /** @return array{0: int, 1: array} HTTP status and JSON body. */
    public static function resolve(string $input, ?User $user): array
    {
        $payload = CaseCode::normalize($input);
        if ($payload === null) {
            return [422, ['message' => 'الرمز غير صحيح، تأكد من الأرقام.']];
        }

        $decoded = json_decode($payload, true);

        if (! is_array($decoded)) {
            return [422, ['message' => 'رمز غير صالح.']];
        }

        if (($decoded['type'] ?? null) === 'task_instance' && ! empty($decoded['id'])) {
            $instance = TaskInstance::with(['task.department', 'task.caseSheetType', 'doctor'])->find($decoded['id']);

            if (! $instance || ! $instance->task) {
                return [404, ['message' => 'حالة المهمة غير موجودة.']];
            }
            if (! self::inScope($instance->task, $user)) {
                return [403, ['message' => 'هذه الحالة خارج الأقسام المسموحة لك.']];
            }

            return [200, [
                'kind' => 'task_instance',
                'instance_id' => $instance->id,
                'status' => $instance->status,
                'doctor' => self::doctor($instance->doctor),
                'task' => [
                    'id' => $instance->task->id,
                    'title' => $instance->task->title,
                    'department' => $instance->task->department?->name,
                    'case_sheet' => $instance->task->caseSheetType?->name_ar,
                ],
                'case_sheet_url' => route('case-sheet.open', $instance->id),
                'card' => $instance->doctor ? self::card($instance->doctor, $instance->task, $instance->id) : null,
                'group' => $instance->doctor ? self::group($instance->doctor) : null,
                'code' => CaseCode::forInstance($instance->id),
            ]];
        }

        if (($decoded['type'] ?? null) === 'pending_task' && ! empty($decoded['task_id']) && ! empty($decoded['doctor_id'])) {
            $task = Task::with(['department', 'caseSheetType'])->find($decoded['task_id']);
            $doctor = Doctor::find($decoded['doctor_id']);

            if (! $task || ! $doctor) {
                return [404, ['message' => 'المهمة أو الطبيب غير موجود.']];
            }
            if (! self::inScope($task, $user)) {
                return [403, ['message' => 'هذه المهمة خارج الأقسام المسموحة لك.']];
            }

            return [200, [
                'kind' => 'pending_task',
                'doctor' => self::doctor($doctor),
                'task' => [
                    'id' => $task->id,
                    'title' => $task->title,
                    'department' => $task->department?->name,
                    'required_count' => $task->required_count,
                    // Its steps, signed in the start dialog (2026-10-18).
                    'scoring' => $task->scoring,
                ],
                // The next slot not started yet; null once the doctor has
                // every required case of this task.
                'card' => self::card($doctor, $task, null),
                'group' => self::group($doctor),
                'code' => CaseCode::forPending($task->id, $doctor->id),
            ]];
        }

        // The doctor's own QR, printed on their ID card (2026-10-14).
        if (($decoded['type'] ?? null) === 'doctor' && ! empty($decoded['id'])) {
            $doctor = Doctor::with(['stage:id,name'])->find($decoded['id']);

            if (! $doctor) {
                return [404, ['message' => 'الطبيب غير موجود.']];
            }

            return [200, [
                'kind' => 'doctor',
                'doctor' => ['id' => $doctor->id, 'name' => $doctor->name, 'stage' => $doctor->stage?->name],
                'progress_url' => route('doctors.progress', $doctor->id),
            ]];
        }

        return [422, ['message' => 'رمز غير معروف — ليس رمز مهمة صالحاً.']];
    }

    private static function doctor(?Doctor $doctor): array
    {
        return ['id' => $doctor?->id, 'name' => $doctor?->name, 'username' => $doctor?->username];
    }

    private static function inScope(Task $task, ?User $user): bool
    {
        if (! $user) {
            return true;
        }
        $allowed = ScopeHelper::allowedDepartmentIds($user);

        return $allowed === null || in_array($task->department_id, $allowed);
    }

    /**
     * The matrix's slot card for this case — or, with no instance, the
     * first slot not started yet.
     */
    private static function card(Doctor $doctor, Task $task, ?int $instanceId): ?array
    {
        $task->loadMissing('caseSheetType:id,type_code,name_ar,icon,color');

        // Same query and order the matrix uses, so the slot numbers match.
        $instances = TaskInstance::where('doctor_id', $doctor->id)
            ->where('task_id', $task->id)
            ->with('assignedBy:id,full_name')
            ->withCount(['attachments', 'attachments as noted_attachments_count' => fn ($q) => $q->whereNotNull('note')])
            ->orderByDesc('status')
            ->orderByDesc('assigned_date')
            ->get();

        $cards = collect(TaskProgressGroupSummary::buildDoctorRow($doctor, collect([$task]), $instances)['tasks']);

        return $instanceId !== null
            ? $cards->firstWhere('instance_id', $instanceId)
            : $cards->firstWhere('status', 'unassigned');
    }

    /** The doctor's group, stage and education type, for the start receipt. */
    private static function group(Doctor $doctor): array
    {
        $sessionId = AcademicSessionHelper::resolveId();
        $group = $doctor->groups()
            ->when($sessionId !== null, fn ($q) => $q->where(function ($q2) use ($sessionId) {
                $q2->where('groups.academic_session_id', $sessionId)->orWhereNull('groups.academic_session_id');
            }))
            ->first();
        $doctor->loadMissing(['stage.educationType']);

        return [
            'id' => $group?->id,
            'name' => $group?->name ?? $doctor->stage?->name ?? '',
            'stage_name' => $doctor->stage?->name,
            'education_type_name' => $doctor->stage?->educationType?->name,
        ];
    }
}
