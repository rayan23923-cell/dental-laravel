<?php

namespace App\Http\Controllers;

use App\Support\TaskScoring;
use App\Models\Doctor;
use App\Services\AcademicSessionHelper;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ports admin/doctor_task_progress.php ("تقدم مهام الطبيب") — per-doctor
 * required/done/remaining breakdown, grouped by task, with the same
 * complete/uncomplete actions as the task-assignment screen
 * (TaskInstanceController::update, reused as-is — no separate endpoint
 * needed here, unlike the original's dedicated toggle_task_instance.php).
 */
class DoctorTaskProgressController extends Controller
{
    public function show(Doctor $doctor): Response
    {
        $sessionId = AcademicSessionHelper::resolveId();

        $group = $doctor->groups()
            ->when($sessionId !== null, fn ($q) => $q->where(function ($q2) use ($sessionId) {
                // Qualified: the members pivot has its own academic_session_id.
                $q2->where('groups.academic_session_id', $sessionId)->orWhereNull('groups.academic_session_id');
            }))
            ->first();

        $instances = $doctor->taskInstances()
            ->with(['task.department', 'task.stage.educationType'])
            ->when($sessionId !== null, fn ($q) => $q->whereHas('task', function ($q2) use ($sessionId) {
                $q2->where('academic_session_id', $sessionId)->orWhereNull('academic_session_id');
            }))
            ->orderByDesc('assigned_date')
            ->orderBy('created_at')
            ->get();

        $stats = [
            'total' => $instances->count(),
            'completed' => $instances->where('status', 'completed')->count(),
            'assigned' => $instances->where('status', 'assigned')->count(),
            'pending' => $instances->where('status', 'pending')->count(),
        ];

        $tasks = $instances->groupBy('task_id')->map(function ($group, $taskId) {
            $task = $group->first()->task;
            $completed = $group->where('status', 'completed')->count();

            return [
                'task_id' => $taskId,
                'title' => $task->title,
                'department' => $task->department?->name,
                'stage' => $task->stage?->name,
                'education_type' => $task->stage?->educationType?->name,
                'required_count' => $task->required_count,
                'completed' => $completed,
                'remaining' => max(0, $task->required_count - $completed),
                'has_options' => ! empty($task->scoring['options'] ?? null),
                'instances' => $group->values()->map(fn ($i) => [
                    'id' => $i->id,
                    'status' => $i->status,
                    'assigned_date' => $i->assigned_date,
                    'completion_date' => $i->completion_date,
                    'notes' => $i->notes,
                    'grade' => $i->grade,
                    'points' => $i->points,
                    'work_items' => $i->work_items,
                ]),
            ];
        })->values();

        return Inertia::render('Doctors/Progress', [
            'doctor' => [
                'id' => $doctor->id,
                'name' => $doctor->name,
                'username' => $doctor->username,
                'stage' => $doctor->stage?->name,
                'education_type' => $doctor->educationType?->name,
                'group' => $group?->name,
            ],
            'stats' => $stats,
            'tasks' => $tasks,
            // Points/percentage per scored department (2026-10-14).
            'scores' => TaskScoring::doctorResults($doctor, $sessionId),
        ]);
    }
}
