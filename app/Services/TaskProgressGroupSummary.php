<?php

namespace App\Services;

use App\Models\Department;
use App\Models\Doctor;
use App\Models\Group;
use App\Models\Stage;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\User;
use App\Support\CaseSheetResolver;
use App\Support\CaseSheetSignatures;
use App\Support\TaskScoring;
use Illuminate\Support\Collection;

/**
 * The department-tabbed doctor/task matrix for one group — extracted from
 * `TaskProgressController::group()` (itself the port of
 * get_group_doctors.php) so the web page and the Flutter API endpoint
 * share one implementation. Already returns raw JSON-shaped (snake_case)
 * arrays, since the web controller fetches this via axios rather than as
 * Inertia props — reusable for the API as-is, no renaming needed.
 */
class TaskProgressGroupSummary
{
    /**
     * $academicSessionId — the active academic year to scope tasks to
     * (null-session tasks always included, same convention as
     * Doctor/Group/Task's own listing endpoints). Previously this method
     * ignored academic year entirely, so a task-progress matrix for a
     * group would blend tasks from every year that ever existed for its
     * stage — the caller resolves the id (usually
     * `AcademicSessionHelper::resolveId()`) rather than this service
     * reaching into the request itself, matching how it already takes
     * every other input as a plain argument.
     */
    public static function build(Group $group, User $user, ?int $academicSessionId = null): array
    {
        $group->load(['stage.educationType']);

        $doctors = $group->doctors()->orderBy('name')->get(['doctors.id', 'doctors.name', 'doctors.username', 'doctors.email']);

        return self::summarize($group->stage_id, $doctors, [
            'id' => $group->id,
            'name' => $group->name,
            'stage_name' => $group->stage?->name,
            'education_type_name' => $group->stage?->educationType?->name,
        ], $user, $academicSessionId);
    }

    /**
     * The same matrix for every doctor of a stage — used while groups are
     * turned off in clinic settings (ClinicSetting::groupsEnabled()), when
     * task progress goes straight from the stage to its doctors. `group.id`
     * is null and `group.stage_id` tells the page what to reload.
     */
    public static function buildForStage(Stage $stage, User $user, ?int $academicSessionId = null): array
    {
        $stage->load('educationType');

        $doctors = Doctor::where('stage_id', $stage->id)
            ->when($academicSessionId, fn ($q) => $q->where(
                fn ($q2) => $q2->where('academic_session_id', $academicSessionId)->orWhereNull('academic_session_id')
            ))
            ->orderBy('name')
            ->get(['id', 'name', 'username', 'email']);

        return self::summarize($stage->id, $doctors, [
            'id' => null,
            'stage_id' => $stage->id,
            'name' => $stage->name,
            'stage_name' => $stage->name,
            'education_type_name' => $stage->educationType?->name,
        ], $user, $academicSessionId);
    }

    private static function summarize(?int $stageId, Collection $doctors, array $header, User $user, ?int $academicSessionId): array
    {
        // Departments of this stage, scoped — these become the tabs.
        $departments = ScopeHelper::scopeDepartments(
            Department::where('stage_id', $stageId),
            $user
        )->orderBy('name')->get(['id', 'name', 'pass_percent']);

        // Every task defined for this stage, with global instance counts,
        // grouped by department (matches the original's tasks_stmt).
        $tasks = Task::where('stage_id', $stageId)
            ->whereIn('department_id', $departments->pluck('id'))
            ->when($academicSessionId, fn ($q) => $q->where(
                fn ($q2) => $q2->where('academic_session_id', $academicSessionId)->orWhereNull('academic_session_id')
            ))
            ->with('caseSheetType:id,type_code,name_ar,icon,color')
            ->withCount([
                'instances as total_instances',
                'instances as pending_count' => fn ($q) => $q->where('status', 'pending'),
                'instances as assigned_count' => fn ($q) => $q->where('status', 'assigned'),
                'instances as completed_count' => fn ($q) => $q->where('status', 'completed'),
            ])
            ->orderBy('title')
            ->get();

        // Every instance belonging to this group's doctors, for these tasks.
        $instances = TaskInstance::whereIn('doctor_id', $doctors->pluck('id'))
            ->whereIn('task_id', $tasks->pluck('id'))
            ->with('assignedBy:id,full_name')
            ->withCount(['attachments', 'attachments as noted_attachments_count' => fn ($q) => $q->whereNotNull('note')])
            ->orderByDesc('status')
            ->orderByDesc('assigned_date')
            ->get();

        $payload = $departments->map(function ($department) use ($tasks, $doctors, $instances) {
            $deptTasks = $tasks->where('department_id', $department->id)->values();

            return [
                'id' => $department->id,
                'name' => $department->name,
                'task_count' => $deptTasks->count(),
                'pass_percent' => $department->pass_percent,
                'total_required' => (int) $deptTasks->sum('required_count'),
                'totals' => [
                    'total_instances' => (int) $deptTasks->sum('total_instances'),
                    'pending' => (int) $deptTasks->sum('pending_count'),
                    'assigned' => (int) $deptTasks->sum('assigned_count'),
                    'completed' => (int) $deptTasks->sum('completed_count'),
                ],
                'doctors' => $doctors->map(fn ($doctor) => self::buildDoctorRow($doctor, $deptTasks, $instances, $department->pass_percent))->values(),
            ];
        })->values();

        return [
            'group' => $header,
            'departments' => $payload,
        ];
    }

    /**
     * One doctor's task-slot cards for one department's tasks — extracted
     * from the inline closure this used to be so `DoctorTaskSummary` (a
     * doctor viewing their own tasks, no `Group` involved) can reuse the
     * exact same positional slot-matching algorithm instead of a second,
     * drifting copy. Pure extraction — same logic, same output shape,
     * verified byte-identical against the pre-refactor admin endpoint
     * response.
     *
     * @param  Collection<int, Task>  $deptTasks
     * @param  Collection<int, TaskInstance>  $instances  All instances for
     *         the relevant doctor(s)/tasks — filtered down to just this
     *         $doctor's own inside this method.
     */
    public static function buildDoctorRow(Doctor $doctor, Collection $deptTasks, Collection $instances, $passPercent = null): array
    {
        $doctorInstances = $instances->where('doctor_id', $doctor->id);

        $completed = 0;
        $assigned = 0;
        $pending = 0;
        $unassigned = 0;
        $taskCards = [];

        foreach ($deptTasks as $task) {
            $required = (int) $task->required_count;
            // Resolved once per task (not per instance) since `$task`
            // already has `caseSheetType` eager-loaded from the query
            // above — avoids `CaseSheetSignatures::allSignedForInstance()`
            // re-fetching `task.caseSheetType` per instance.
            $resource = CaseSheetResolver::resourceForTask($task);
            // The original keys each doctor's cards by slot index
            // 0..required-1 against their own instances for that
            // task — there is no per-slot FK, it's positional.
            $own = $doctorInstances->where('task_id', $task->id)->values();

            foreach ($own as $instance) {
                match ($instance->status) {
                    'completed' => $completed++,
                    'assigned' => $assigned++,
                    'pending' => $pending++,
                    default => null,
                };
            }
            $unassigned += max(0, $required - $own->count());

            for ($slot = 0; $slot < $required; $slot++) {
                $instance = $own[$slot] ?? null;

                $taskCards[] = [
                    'slot' => $slot + 1,
                    'task_id' => $task->id,
                    'task_title' => $task->title,
                    'task_notes' => $task->notes,
                    'task_grade' => $task->grade,
                    // Work options/multipliers for the complete dialog (2026-10-14).
                    'task_scoring' => $task->scoring,
                    'case_sheet' => $task->caseSheetType ? [
                        'name' => $task->caseSheetType->name_ar,
                        'color' => $task->caseSheetType->color,
                    ] : null,
                    'instance_id' => $instance?->id,
                    // 'unassigned' is not a DB status — it's the
                    // computed "slot exists but no instance row
                    // yet" state the original renders as
                    // "لم تبدأ بعد".
                    'status' => $instance?->status ?? 'unassigned',
                    'assigned_date' => $instance?->assigned_date,
                    'completion_date' => $instance?->completion_date,
                    'notes' => $instance?->notes,
                    'grade' => $instance?->grade,
                    'points' => $instance?->points,
                    'work_items' => $instance?->work_items,
                    // Steps to sign one after another (2026-10-18); see TaskSteps.
                    'steps_count' => count(\App\Support\TaskSteps::list($task)),
                    'steps_signed' => count($instance?->step_signoffs ?? []),
                    // Who started this task — lets the client
                    // (re)print the start receipt at any time,
                    // not only at the moment of starting.
                    'started_by' => $instance?->assignedBy?->full_name,
                    // "شكرا، تم توثيقه ورقياً" (2026-08-28) — purely
                    // informational; drives a badge/button on the
                    // client only, never gates the electronic form.
                    'paper_case_sheet_confirmed_at' => $instance?->paper_case_sheet_confirmed_at,
                    // Photos of the paper case sheet (2026-10-13).
                    'attachments_count' => $instance?->attachments_count ?? 0,
                    // Photos the supervisor wrote a note on (2026-10-15).
                    'noted_attachments_count' => $instance?->noted_attachments_count ?? 0,
                    // Surfaces a "ready to mark complete" hint next to the
                    // existing complete button (2026-08-30, by request) —
                    // never completes anything itself, see
                    // App\Support\CaseSheetSignatures's class doc comment.
                    'all_signed' => $instance && $instance->status === 'assigned'
                        ? CaseSheetSignatures::allSignedForInstance($resource, $instance)
                        : false,
                ];
            }
        }

        return [
            'id' => $doctor->id,
            'name' => $doctor->name,
            'username' => $doctor->username,
            'required' => (int) $deptTasks->sum('required_count'),
            'completed' => $completed,
            'assigned' => $assigned,
            'pending' => $pending,
            'unassigned' => $unassigned,
            'tasks' => $taskCards,
            // Points, percentage and pass/fail (2026-10-14); null for a
            // department that is only counted in cases.
            'score' => TaskScoring::doctorResult($deptTasks, $doctorInstances, $passPercent),
        ];
    }
}
