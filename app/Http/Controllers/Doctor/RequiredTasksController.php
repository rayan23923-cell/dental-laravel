<?php

namespace App\Http\Controllers\Doctor;

use App\Http\Controllers\Controller;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\AcademicSessionHelper;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "المهام المطلوبة حسب الأقسام" — port of
 * dental_clinics2/doctor/required_tasks.php: the doctor's stage tasks
 * grouped by department, with one card per required slot showing that
 * slot's status, the same positional slot model as the admin task-progress
 * screen (see TaskProgressController).
 */
class RequiredTasksController extends Controller
{
    public function index(): Response
    {
        $doctor = Auth::guard('doctor')->user();
        $doctor->load('stage');
        $sessionId = AcademicSessionHelper::resolveId();

        $tasks = Task::where('stage_id', $doctor->stage_id)
            ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->with(['department:id,name', 'caseSheetType:id,name_ar,color'])
            ->orderBy('title')
            ->get();

        $instances = TaskInstance::where('doctor_id', $doctor->id)
            ->whereIn('task_id', $tasks->pluck('id'))
            ->orderBy('id')
            ->get();

        $departments = $tasks
            ->groupBy(fn ($t) => $t->department?->name ?? 'Unassigned')
            ->map(function ($deptTasks, $name) use ($instances) {
                $rows = $deptTasks->map(function ($task) use ($instances) {
                    $own = $instances->where('task_id', $task->id)->values();
                    $required = (int) $task->required_count;

                    $slots = [];
                    for ($i = 0; $i < $required; $i++) {
                        $instance = $own[$i] ?? null;
                        $slots[] = [
                            'slot' => $i + 1,
                            'instance_id' => $instance?->id,
                            // 'unassigned' is computed, not a DB status —
                            // the original renders it as "لم تبدأ بعد".
                            'status' => $instance?->status ?? 'unassigned',
                            'assigned_date' => $instance?->assigned_date,
                            'completion_date' => $instance?->completion_date,
                            'notes' => $instance?->notes,
                            'grade' => $instance?->grade,
                            // "شكرا، تم توثيقه ورقياً" (2026-08-28) — purely
                            // informational, drives the badge/button state
                            // only; never gates the electronic form link
                            // above it.
                            'paper_case_sheet_confirmed_at' => $instance?->paper_case_sheet_confirmed_at,
                        ];
                    }

                    return [
                        'id' => $task->id,
                        'title' => $task->title,
                        'case_sheet' => $task->caseSheetType?->name_ar,
                        'notes' => $task->notes,
                        'grade' => $task->grade,
                        'required_count' => $required,
                        'completed' => $own->where('status', 'completed')->count(),
                        'remaining' => max(0, $required - $own->where('status', 'completed')->count()),
                        'slots' => $slots,
                    ];
                })->values();

                return [
                    'name' => $name,
                    'tasks' => $rows,
                    'required' => (int) $rows->sum('required_count'),
                    'completed' => (int) $rows->sum('completed'),
                ];
            })->values();

        return Inertia::render('Doctor/RequiredTasks', [
            'stage' => $doctor->stage?->name,
            'departments' => $departments,
        ]);
    }
}
