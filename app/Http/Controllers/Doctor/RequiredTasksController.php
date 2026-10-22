<?php

namespace App\Http\Controllers\Doctor;

use App\Http\Controllers\Controller;
use App\Http\Controllers\FormSettingsController;
use App\Support\FormSettings;
use App\Support\TaskSteps;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Models\TaskStartRequest;
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
            ->withCount(['attachments', 'attachments as noted_attachments_count' => fn ($q) => $q->whereNotNull('note')])
            ->orderBy('id')
            ->get();

        // "طلبات بدء المهام" (2026-10-14): the doctor's own requests.
        $requests = TaskStartRequest::where('doctor_id', $doctor->id)->latest()->limit(200)->get();
        $pendingTaskIds = $requests->where('status', 'pending')->pluck('task_id')->map(fn ($id) => (int) $id)->all();

        $departments = $tasks
            ->groupBy(fn ($t) => $t->department?->name ?? 'Unassigned')
            ->map(function ($deptTasks, $name) use ($instances, $pendingTaskIds) {
                $rows = $deptTasks->map(function ($task) use ($instances, $pendingTaskIds) {
                    $own = $instances->where('task_id', $task->id)->values();
                    $required = (int) $task->required_count;

                    $slots = [];
                    for ($i = 0; $i < $required; $i++) {
                        $instance = $own[$i] ?? null;
                        $steps = $instance && FormSettings::on('steps_enabled') ? TaskSteps::list($task, $instance) : [];
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
                            // Photos of the paper case sheet (2026-10-13).
                            'attachments_count' => $instance?->attachments_count ?? 0,
                            // Photos the supervisor wrote a note on (2026-10-15).
                            'noted_attachments_count' => $instance?->noted_attachments_count ?? 0,
                            // Steps signed so far, for the supervisor code (2026-10-22).
                            'steps_count' => count($steps),
                            'steps_signed' => collect($steps)->where('signed', true)->count(),
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
                        'department' => $task->department?->name,
                        'request_pending' => in_array((int) $task->id, $pendingTaskIds, true),
                    ];
                })->values();

                return [
                    'name' => $name,
                    'tasks' => $rows,
                    'required' => (int) $rows->sum('required_count'),
                    'completed' => (int) $rows->sum('completed'),
                ];
            })->values();

        $departments = $departments->values()->toArray();

        return Inertia::render('Doctor/RequiredTasks', [
            'stage' => $doctor->stage?->name,
            // Grades hidden from students in forms settings (2026-10-22).
            'departments' => FormSettings::gradesShownToDoctors() ? $departments : FormSettings::withoutGrades($departments),
            'requests' => $requests->map->toView()->values(),
            // Forms on offer and the supervisor code (2026-10-22).
            'formSettings' => (new FormSettingsController)->forDoctor()->getData(true),
        ]);
    }
}
