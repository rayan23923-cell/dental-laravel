<?php

namespace App\Http\Controllers;

use App\Models\TaskInstance;
use App\Models\User;
use App\Services\CaseSheetAccess;
use App\Services\PermissionManager;
use App\Support\TaskScoring;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The task's points on its case sheet (2026-10-15, by request: "النقاط
 * المدخلة في المهام تتزامن مع النماذج"). A case sheet linked to a scored
 * task shows the task's work, grades and checklist; they live on the task
 * instance, the same record the task-progress complete/edit dialogs write,
 * so both places always show the same points. Staff who may finish tasks
 * edit them here; the doctor sees them.
 */
class TaskWorkController extends Controller
{
    public function show(TaskInstance $taskInstance): JsonResponse
    {
        $doctor = CaseSheetAccess::doctor();
        abort_if($doctor && (int) $taskInstance->doctor_id !== (int) $doctor->id, 403);
        // Staff read it with the case sheet it sits on (2026-10-18).
        abort_if(! $doctor && ! $this->can('open_case_sheet'), 403);

        $taskInstance->loadMissing('task');
        // A task graded by its sheet's steps shows what the sheet adds up to now.
        $fromSheet = TaskScoring::pointsFromCaseSheet($taskInstance);

        return response()->json([
            'title' => $taskInstance->task?->title,
            'scoring' => $taskInstance->task?->scoring,
            'status' => $taskInstance->status,
            'work_items' => $fromSheet[0] ?? $taskInstance->work_items ?? [],
            'points' => $fromSheet[1] ?? $taskInstance->points,
            'from_sheet' => $fromSheet !== null,
            'can_edit' => ! $doctor && $this->canEdit(),
        ]);
    }

    public function update(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        abort_unless($this->canEdit(), 403);
        $taskInstance->loadMissing('task');

        // Steps added by hand to a sheet-graded task are graded here (2026-10-16).
        if (TaskScoring::stepsMax($taskInstance->task?->scoring) !== null && ! TaskScoring::pointsOff($taskInstance->task?->scoring)) {
            $grades = $request->validate([
                'step_grades' => ['nullable', 'array'],
                'step_grades.*' => ['nullable', 'numeric', 'min:0'],
            ])['step_grades'] ?? [];
            [$items, $points] = TaskScoring::pointsFromCaseSheet($taskInstance, $grades);
            $taskInstance->update(['work_items' => $items, 'points' => $points]);

            return response()->json(['work_items' => $items, 'points' => $taskInstance->points]);
        }

        $validated = $request->validate(TaskScoring::workItemRules());

        // Saved as progress: an unfinished checklist is fine until the case is completed.
        $resolved = TaskScoring::resolveWorkItems($taskInstance->task, $validated['work_items'] ?? [], requireChecklist: $taskInstance->status === 'completed');
        [$items, $points] = $resolved ?? [[], 0];
        $scored = ! TaskScoring::pointsOff($taskInstance->task?->scoring)
            && collect($items)->contains(fn ($item) => empty($item['check']) || ! empty($item['scored']));
        $taskInstance->update(['work_items' => $items, 'points' => $scored ? $points : null]);

        return response()->json(['work_items' => $items, 'points' => $taskInstance->points]);
    }

    private function canEdit(): bool
    {
        return $this->can('finish');
    }

    private function can(string $permission): bool
    {
        $user = request()->user();

        return $user instanceof User && (new PermissionManager($user))->can('task_progress', $permission);
    }
}
