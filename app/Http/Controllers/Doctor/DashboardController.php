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
 * Doctor dashboard — port of dental_clinics2/doctor/index.php.
 *
 * Reproduces its real behaviour, not just a task list:
 *  - the doctor's study type / stage / group and that group's weekly slots;
 *  - four stat cards (displayed tasks, completed, assigned, pending) and a
 *    completion progress bar, all computed over the *displayed* tasks only,
 *    exactly as the original does;
 *  - the "started tasks" filter: once the doctor has any assigned or
 *    completed instance, the list hides tasks that have neither a pending
 *    nor an assigned instance — the original shows a dismissible notice
 *    explaining this, ported alongside it.
 */
class DashboardController extends Controller
{
    public function index(): Response
    {
        $doctor = Auth::guard('doctor')->user();
        $doctor->load(['stage.educationType', 'groups.slots']);

        $group = $doctor->groups->first();
        $sessionId = AcademicSessionHelper::resolveId();

        // Once anything is under way, the original stops showing tasks that
        // have no pending/assigned instance left.
        $hasStartedTasks = TaskInstance::where('doctor_id', $doctor->id)
            ->whereIn('status', ['assigned', 'completed'])
            ->exists();

        $tasks = Task::where('stage_id', $doctor->stage_id)
            ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->with(['department:id,name', 'caseSheetType:id,name_ar,color'])
            ->withCount([
                'instances as total_instances',
                'instances as pending_instances' => fn ($q) => $q->where('status', 'pending'),
                // The original counts assigned/completed for *this doctor*
                // but pending globally (a pending instance belongs to nobody
                // yet) — that asymmetry is deliberate and kept.
                'instances as assigned_instances' => fn ($q) => $q->where('status', 'assigned')->where('doctor_id', $doctor->id),
                'instances as completed_instances' => fn ($q) => $q->where('status', 'completed')->where('doctor_id', $doctor->id),
            ])
            ->orderBy('title')
            ->get()
            ->when($hasStartedTasks, fn ($all) => $all->filter(
                fn ($t) => $t->pending_instances > 0 || $t->assigned_instances > 0
            ))
            ->values();

        $totalInstances = (int) $tasks->sum('total_instances');
        $completed = (int) $tasks->sum('completed_instances');
        $assigned = (int) $tasks->sum('assigned_instances');
        $pending = (int) $tasks->sum('pending_instances');

        return Inertia::render('Doctor/Dashboard', [
            'doctorInfo' => [
                'name' => $doctor->name,
                'education_type' => $doctor->stage?->educationType?->name,
                'stage' => $doctor->stage?->name,
                'group' => $group?->name,
                'slots' => $group?->slots->map(fn ($s) => [
                    'day' => $s->day,
                    'start' => substr($s->start_time, 0, 5),
                    'end' => substr($s->end_time, 0, 5),
                ])->values() ?? [],
            ],
            'hasStartedTasks' => $hasStartedTasks,
            'stats' => [
                'tasks' => $tasks->count(),
                'total_instances' => $totalInstances,
                'completed' => $completed,
                'assigned' => $assigned,
                'pending' => $pending,
                'progress' => $totalInstances > 0 ? round(($completed / $totalInstances) * 100, 1) : 0,
            ],
            'tasks' => $tasks->map(fn ($t) => [
                'id' => $t->id,
                'title' => $t->title,
                'department' => $t->department?->name,
                'case_sheet' => $t->caseSheetType?->name_ar,
                'notes' => $t->notes,
                'grade' => $t->grade,
                'required_count' => $t->required_count,
                'total_instances' => $t->total_instances,
                'pending' => $t->pending_instances,
                'assigned' => $t->assigned_instances,
                'completed' => $t->completed_instances,
            ])->values(),
        ]);
    }
}
