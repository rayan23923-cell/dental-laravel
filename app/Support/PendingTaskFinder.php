<?php

namespace App\Support;

use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\AcademicSessionHelper;
use Illuminate\Database\Eloquent\Collection;

/**
 * Extracted from `Doctor\PendingTasksQrController::index()`, which was
 * guard-bound to `Auth::guard('doctor')->user()` — the doctor viewing their
 * own pending tasks. `Api\TaskProgressController`'s NFC lookup needs the
 * identical "pending" definition for an *arbitrary* doctor a staff member
 * just scanned, hence the extraction rather than a second copy.
 *
 * "Pending" here means a task in the doctor's stage that the doctor has
 * **no `TaskInstance` of at all** — i.e. not yet started, a different sense
 * from `task_instances.status='pending'`.
 */
class PendingTaskFinder
{
    public static function forDoctor(Doctor $doctor): Collection
    {
        $sessionId = AcademicSessionHelper::resolveId();
        $startedTaskIds = TaskInstance::where('doctor_id', $doctor->id)->distinct()->pluck('task_id');

        return Task::where('stage_id', $doctor->stage_id)
            ->whereNotIn('id', $startedTaskIds)
            ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id')))
            ->with('department:id,name')
            ->orderBy('title')
            ->get();
    }
}
