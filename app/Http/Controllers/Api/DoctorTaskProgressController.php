<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AcademicSession;
use App\Models\Doctor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\DoctorTaskProgressController for the
 * Flutter client. Sessionless like the rest of the API (see
 * App\Services\AcademicSessionHelper's docblock) — takes an optional
 * ?academic_session_id= to scope by, falling back to whichever session has
 * is_current=true.
 */
class DoctorTaskProgressController extends Controller
{
    public function show(Request $request, Doctor $doctor): JsonResponse
    {
        $sessionId = $request->integer('academic_session_id')
            ?: AcademicSession::where('is_current', true)->value('id');

        $group = $doctor->groups()
            ->when($sessionId, fn ($q) => $q->where(function ($q2) use ($sessionId) {
                $q2->where('academic_session_id', $sessionId)->orWhereNull('academic_session_id');
            }))
            ->first();

        $instances = $doctor->taskInstances()
            ->with(['task.department', 'task.stage.educationType'])
            ->when($sessionId, fn ($q) => $q->whereHas('task', function ($q2) use ($sessionId) {
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
                'instances' => $group->values(),
            ];
        })->values();

        return response()->json([
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
        ]);
    }
}
