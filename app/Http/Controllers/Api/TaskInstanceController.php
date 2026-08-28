<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\TaskInstanceResource;
use App\Models\Doctor;
use App\Models\TaskInstance;
use App\Support\TaskInstanceVisibility;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TaskInstanceController extends Controller
{
    /**
     * Task instances assigned to the currently authenticated doctor.
     * This is the primary endpoint the Flutter doctor app polls for its
     * "my tasks" list.
     */
    public function mine(Request $request): JsonResponse
    {
        $doctor = $request->user();

        abort_unless($doctor instanceof Doctor, 403, 'Only doctors have a task list.');

        $instances = TaskInstance::with(['task.department', 'task.caseSheetType'])
            ->where('doctor_id', $doctor->id)
            ->when($request->string('status')->toString(), fn ($q, $status) => $q->where('status', $status))
            ->orderByDesc('id')
            ->paginate(20);

        return TaskInstanceResource::collection($instances)->response();
    }

    public function show(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $doctor = $request->user();

        if ($doctor instanceof Doctor) {
            abort_unless($taskInstance->doctor_id === $doctor->id, 403);
        }

        $taskInstance->load(['task.department', 'task.caseSheetType']);
        if (TaskInstanceVisibility::canSeeStudentInfo($doctor)) {
            $taskInstance->load(['doctor', 'assignedBy']);
        }

        return (new TaskInstanceResource($taskInstance))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'task_id' => ['required', 'exists:tasks,id'],
            'doctor_id' => ['required', 'exists:doctors,id'],
        ]);

        $instance = TaskInstance::create([
            ...$validated,
            'status' => 'assigned',
            'assigned_date' => now(),
            'assigned_by' => $request->user()->id,
        ]);

        return (new TaskInstanceResource($instance))->response()->setStatusCode(201);
    }

    public function update(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $doctor = $request->user();

        if ($doctor instanceof Doctor) {
            abort_unless($taskInstance->doctor_id === $doctor->id, 403);
        }

        $validated = $request->validate([
            'status' => ['required', 'in:pending,assigned,completed'],
            'grade' => ['nullable', 'numeric', 'min:0', 'max:999.99'],
            'notes' => ['nullable', 'string'],
        ]);

        if ($validated['status'] === 'completed' && $taskInstance->status !== 'completed') {
            $validated['completion_date'] = now();
        } elseif ($validated['status'] !== 'completed' && $taskInstance->status === 'completed') {
            $validated['completion_date'] = null;
        }

        $taskInstance->update($validated);

        return (new TaskInstanceResource($taskInstance))->response();
    }

    public function destroy(TaskInstance $taskInstance): JsonResponse
    {
        $taskInstance->delete();

        return response()->json(null, 204);
    }

    /**
     * "شكرا، تم توثيقه ورقياً" (2026-08-28) — a doctor may mark their own
     * case as documented on paper instead of filling the electronic case
     * sheet. Purely a non-exclusive confirmation tag, not a mode switch:
     * this never blocks or hides the "نموذج سريري" flow (both stay
     * available, per the user's explicit confirmation) — it only sets
     * when/who confirmed, same shape as `screening_checked_by`/
     * `screening_checked_at` on `patients_simple`.
     */
    public function confirmPaper(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $doctor = $request->user();
        abort_unless($doctor instanceof Doctor, 403);
        abort_unless($taskInstance->doctor_id === $doctor->id, 403);

        $taskInstance->update([
            'paper_case_sheet_confirmed_by' => $doctor->id,
            'paper_case_sheet_confirmed_at' => now(),
        ]);

        return (new TaskInstanceResource($taskInstance))->response();
    }
}
