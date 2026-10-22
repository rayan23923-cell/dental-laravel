<?php

namespace App\Services;

use App\Models\TaskInstance;
use App\Support\FormSettings;
use App\Support\TaskScoring;

/**
 * Grade validation + the two mutations that apply it — extracted from
 * `TaskProgressController::complete()`/`updateInstance()`/`validateGrade()`
 * so the web page and the Flutter API endpoint enforce the identical rule
 * (a grade may only be set when the task itself defines one, and may never
 * exceed it) rather than a second, potentially-drifting copy.
 */
class TaskInstanceGrader
{
    /** @throws TaskGradeException */
    public static function validateGrade(TaskInstance $taskInstance, $grade): void
    {
        if ($grade === null || $grade === '' || ! FormSettings::on('grade_entry_enabled')) {
            return;
        }

        $taskGrade = $taskInstance->task?->grade;

        if ($taskGrade === null) {
            throw new TaskGradeException("A grade can't be set — this task has no grade defined.");
        }

        if ((float) $grade > (float) $taskGrade) {
            throw new TaskGradeException(sprintf("The grade (%.2f) can't exceed the task's grade (%.2f).", $grade, $taskGrade));
        }
    }

    /** @throws TaskGradeException */
    public static function complete(TaskInstance $taskInstance, $grade, $notes, ?array $workItems = null): void
    {
        // Completing tasks switched off for the whole system (2026-10-22).
        if (! FormSettings::on('task_finish_enabled')) {
            throw new TaskGradeException('إكمال المهام متوقف حالياً من إعدادات النماذج.');
        }
        static::validateGrade($taskInstance, $grade);
        // Grades switched off: the grade already there stays as it is.
        if (! FormSettings::on('grade_entry_enabled')) {
            $grade = null;
        }

        $taskInstance->update([
            'status' => 'completed',
            'completion_date' => now(),
            'grade' => $grade ?? $taskInstance->grade,
            'notes' => $notes ?? $taskInstance->notes,
            ...static::work($taskInstance, $workItems),
        ]);
    }

    /**
     * The work done and its points (2026-10-14), resolved against the
     * task's own options so the points always follow its setup; nothing
     * when the client sent no `work_items`.
     */
    private static function work(TaskInstance $taskInstance, ?array $workItems): array
    {
        // A task graded by its case sheet's steps takes its points from there.
        $resolved = TaskScoring::pointsFromCaseSheet($taskInstance)
            ?? TaskScoring::resolveWorkItems($taskInstance->task, $workItems);
        if ($resolved === null) {
            return [];
        }
        [$items, $points] = $resolved;

        // Ticked checklist parts carry no points of their own unless graded.
        $scored = ! TaskScoring::pointsOff($taskInstance->task?->scoring)
            && collect($items)->contains(fn ($item) => empty($item['check']) || ! empty($item['scored']));

        return ['work_items' => $items, 'points' => $scored ? $points : null];
    }

    /** @throws TaskGradeException */
    public static function updateNotesGrade(TaskInstance $taskInstance, $grade, $notes, ?array $workItems = null): void
    {
        static::validateGrade($taskInstance, $grade);
        if (! FormSettings::on('grade_entry_enabled')) {
            $grade = $taskInstance->grade;
        }

        $taskInstance->update([
            'grade' => $grade,
            'notes' => $notes,
            ...static::work($taskInstance, $workItems),
        ]);
    }
}
