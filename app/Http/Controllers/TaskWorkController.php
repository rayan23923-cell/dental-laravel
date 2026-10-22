<?php

namespace App\Http\Controllers;

use App\Models\TaskInstance;
use App\Models\User;
use App\Services\CaseSheetAccess;
use App\Services\PermissionManager;
use App\Support\CaseSheetSignatures;
use App\Support\FormSettings;
use App\Support\TaskScoring;
use App\Support\TaskSteps;
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

        $payload = [
            'title' => $taskInstance->task?->title,
            'scoring' => $taskInstance->task?->scoring,
            'status' => $taskInstance->status,
            'work_items' => $fromSheet[0] ?? $taskInstance->work_items ?? [],
            'points' => $fromSheet[1] ?? $taskInstance->points,
            'from_sheet' => $fromSheet !== null,
            'can_edit' => ! $doctor && $this->canEdit() && FormSettings::on('grade_entry_enabled'),
            // System-wide switches (2026-10-22).
            'grades_on' => FormSettings::on('grade_entry_enabled'),
            'can_add_step' => ! $doctor && $this->can('add_step') && FormSettings::on('step_add_enabled') && FormSettings::on('steps_enabled'),
            // Its steps, signed one after another (2026-10-18); none while
            // steps are switched off for the whole system (2026-10-22).
            'steps' => FormSettings::on('steps_enabled') ? TaskSteps::list($taskInstance->task, $taskInstance) : [],
            'can_sign' => ! $doctor && $this->canSign() && FormSettings::on('steps_enabled'),
        ];
        // Grades hidden from students in forms settings, and from staff
        // without `view_grade` (2026-10-22).
        $showGrades = $doctor ? FormSettings::gradesShownToDoctors() : $this->can('view_grade');
        if (! $showGrades) {
            $payload = FormSettings::withoutGrades($payload);
        }

        return response()->json($payload);
    }

    /** Signs the case's next step with its grade (2026-10-18), see TaskSteps. */
    public function signStep(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        abort_unless($this->canSign(), 403);
        $validated = $request->validate([
            'step' => ['required', 'string', 'max:40'],
            'grade' => ['nullable', 'numeric', 'min:0'],
        ]);
        TaskSteps::sign($taskInstance, $validated['step'], $validated['grade'] ?? null, CaseSheetSignatures::signerName($request));

        return $this->show($taskInstance->fresh());
    }

    /** Takes back the last signed step. */
    public function undoStep(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        abort_unless($this->canSign(), 403);
        $validated = $request->validate(['step' => ['required', 'string', 'max:40']]);
        TaskSteps::undo($taskInstance, $validated['step']);

        return $this->show($taskInstance->fresh());
    }

    /** Adds a step with its name and top grade to this case (2026-10-19, by request). */
    public function addExtraStep(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        // Its own permission (2026-10-22, was signing steps).
        abort_unless($this->can('add_step'), 403);
        $validated = $request->validate([
            'label' => ['required', 'string', 'max:100'],
            'max' => ['required', 'numeric', 'min:0.5', 'max:100'],
        ]);
        TaskSteps::addExtra($taskInstance, trim($validated['label']), (float) $validated['max']);

        return $this->show($taskInstance->fresh());
    }

    /** Removes a step added to this case while it is unsigned. */
    public function removeExtraStep(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        abort_unless($this->canSign(), 403);
        $validated = $request->validate(['step' => ['required', 'string', 'max:40']]);
        TaskSteps::removeExtra($taskInstance, $validated['step']);

        return $this->show($taskInstance->fresh());
    }

    /** Signing steps is its own permission (2026-10-22, was start or finish). */
    private function canSign(): bool
    {
        return $this->can('track_steps');
    }

    public function update(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        abort_unless($this->canEdit(), 403);
        abort_unless(FormSettings::on('grade_entry_enabled'), 422, 'إدخال الدرجات متوقف حالياً من إعدادات النماذج.');
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
        // Steps added to this case keep their signed grades.
        $extras = collect($taskInstance->work_items ?? [])->filter(fn ($item) => ! empty($item['extra']))->values();
        $items = [...$items, ...$extras->all()];
        $points += $extras->sum('points');
        $scored = ! TaskScoring::pointsOff($taskInstance->task?->scoring)
            && collect($items)->contains(fn ($item) => empty($item['check']) || ! empty($item['scored']));
        $taskInstance->update(['work_items' => $items, 'points' => $scored ? $points : null]);

        return response()->json(['work_items' => $items, 'points' => $taskInstance->points]);
    }

    /** Adding and editing grades is its own permission (2026-10-22, was finish). */
    private function canEdit(): bool
    {
        return $this->can('grade');
    }

    private function can(string $permission): bool
    {
        $user = request()->user();

        return $user instanceof User && (new PermissionManager($user))->can('task_progress', $permission);
    }
}
