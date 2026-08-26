<?php

namespace App\Services;

use App\Models\TaskInstance;

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
        if ($grade === null || $grade === '') {
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
    public static function complete(TaskInstance $taskInstance, $grade, $notes): void
    {
        static::validateGrade($taskInstance, $grade);

        $taskInstance->update([
            'status' => 'completed',
            'completion_date' => now(),
            'grade' => $grade ?? $taskInstance->grade,
            'notes' => $notes ?? $taskInstance->notes,
        ]);
    }

    /** @throws TaskGradeException */
    public static function updateNotesGrade(TaskInstance $taskInstance, $grade, $notes): void
    {
        static::validateGrade($taskInstance, $grade);

        $taskInstance->update([
            'grade' => $grade,
            'notes' => $notes,
        ]);
    }
}
