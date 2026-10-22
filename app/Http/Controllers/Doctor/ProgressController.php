<?php

namespace App\Http\Controllers\Doctor;

use App\Http\Controllers\Controller;
use App\Services\AcademicSessionHelper;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "تقدم المهام التفصيلي" — port of dental_clinics2/doctor/progress.php:
 * the doctor's own instances grouped by task, with per-task and overall
 * completion. Same computation as the admin-side per-doctor screen
 * (DoctorTaskProgressController), scoped to the logged-in doctor.
 */
class ProgressController extends Controller
{
    public function index(): Response
    {
        $doctor = Auth::guard('doctor')->user();
        $sessionId = AcademicSessionHelper::resolveId();

        $instances = $doctor->taskInstances()
            ->with(['task.department', 'task.caseSheetType'])
            ->when($sessionId, fn ($q) => $q->whereHas('task', fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->orderByDesc('assigned_date')
            ->orderBy('created_at')
            ->get();

        $tasks = $instances->groupBy('task_id')->map(function ($group) {
            $task = $group->first()->task;
            $completed = $group->where('status', 'completed')->count();

            return [
                'task_id' => $task->id,
                'title' => $task->title,
                'department' => $task->department?->name,
                'case_sheet' => $task->caseSheetType?->name_ar,
                'required_count' => (int) $task->required_count,
                'completed' => $completed,
                'remaining' => max(0, (int) $task->required_count - $completed),
                'instances' => $group->values()->map(fn ($i) => [
                    'id' => $i->id,
                    'status' => $i->status,
                    'assigned_date' => $i->assigned_date,
                    'completion_date' => $i->completion_date,
                    'notes' => $i->notes,
                    'grade' => $i->grade,
                ]),
            ];
        })->values();

        return Inertia::render('Doctor/Progress', [
            'stats' => [
                'total' => $instances->count(),
                'completed' => $instances->where('status', 'completed')->count(),
                'assigned' => $instances->where('status', 'assigned')->count(),
                'pending' => $instances->where('status', 'pending')->count(),
            ],
            // Grades hidden from students in forms settings (2026-10-22).
            'tasks' => \App\Support\FormSettings::gradesShownToDoctors() ? $tasks : \App\Support\FormSettings::withoutGrades($tasks->toArray()),
        ]);
    }
}
