<?php

namespace App\Services;

use App\Models\Department;
use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;

/**
 * A doctor's own department-grouped task summary — the single-doctor
 * equivalent of `TaskProgressGroupSummary::build()` (which is for staff
 * viewing a group of *many* doctors). Reuses that same class's
 * `buildDoctorRow()` — the identical positional slot-matching algorithm
 * (no per-slot FK; a task requiring N cases always renders N slots,
 * matched against the doctor's own instances by index) — rather than a
 * second, drifting copy.
 *
 * No `Group` context needed: a doctor's own tasks are purely a function of
 * their `stage_id`, exactly like `TaskProgressGroupSummary` scopes by
 * `$group->stage_id`. No `ScopeHelper` staff-scoping either — that's for
 * restricting what *staff* can see, irrelevant to a doctor viewing their
 * own data.
 */
class DoctorTaskSummary
{
    // $academicSessionId — see TaskProgressGroupSummary::build()'s
    // matching parameter doc comment; same convention, same reason.
    public static function build(Doctor $doctor, ?int $academicSessionId = null): array
    {
        $departments = Department::where('stage_id', $doctor->stage_id)
            ->orderBy('name')
            ->get(['id', 'name', 'pass_percent']);

        $tasks = Task::where('stage_id', $doctor->stage_id)
            ->whereIn('department_id', $departments->pluck('id'))
            ->when($academicSessionId, fn ($q) => $q->where(
                fn ($q2) => $q2->where('academic_session_id', $academicSessionId)->orWhereNull('academic_session_id')
            ))
            ->with('caseSheetType:id,type_code,name_ar,icon,color')
            ->orderBy('title')
            ->get();

        $instances = TaskInstance::where('doctor_id', $doctor->id)
            ->whereIn('task_id', $tasks->pluck('id'))
            ->with('assignedBy:id,full_name')
            ->withCount('attachments')
            ->get();

        return [
            'departments' => $departments->map(function ($department) use ($tasks, $doctor, $instances) {
                $deptTasks = $tasks->where('department_id', $department->id)->values();

                return [
                    'id' => $department->id,
                    'name' => $department->name,
                    'doctor' => TaskProgressGroupSummary::buildDoctorRow($doctor, $deptTasks, $instances, $department->pass_percent),
                ];
            })->values(),
        ];
    }
}
