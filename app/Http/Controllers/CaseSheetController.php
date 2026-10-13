<?php

namespace App\Http\Controllers;

use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\PermissionManager;
use App\Support\CaseSheetResolver;
use App\Support\CaseSheetReturn;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;

/**
 * Case-sheet dispatcher — port of dental_clinics2/doctor/open_case_sheet.php.
 *
 * **This is the mechanism the earlier port was missing.** In the original,
 * case sheets are never browsed as standalone lists: a task carries a
 * `case_sheet_type_id`, and opening a task instance routes to the matching
 * sheet by that type's `type_code`, carrying `task_instances_id` so the
 * sheet loads/saves the record belonging to *that* instance. The port had
 * built the sheets themselves but only as independent CRUD screens, so
 * nothing tied a filled sheet back to the task it was filled for.
 *
 * Access mirrors the original: a doctor may only open their own instance;
 * a staff user needs the `task_progress.open_case_sheet` permission (the
 * original checks exactly that, and it is one of the actions restored to
 * the permission matrix).
 *
 * The `type_code` → resource map and the "does a record already exist for
 * this instance" lookup live in `App\Support\CaseSheetResolver` (extracted
 * 2026-08-27) so `Api\CaseSheetController` — Flutter's equivalent of this
 * same dispatch — resolves a case exactly the same way instead of via a
 * second, divergent copy of the map.
 */
class CaseSheetController extends Controller
{
    public function open(TaskInstance $taskInstance): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();

        if ($doctor) {
            // A doctor may only open their own instance.
            abort_unless($taskInstance->doctor_id === $doctor->id, 403);
        } else {
            $user = Auth::user();
            abort_unless($user && (new PermissionManager($user))->can('task_progress', 'open_case_sheet'), 403);
        }

        $resource = CaseSheetResolver::resourceFor($taskInstance);
        CaseSheetReturn::remember();

        // Reuse the sheet already filled for this instance if there is one,
        // otherwise open a blank sheet pre-linked to it — this is what makes
        // the sheet belong to the task rather than float free.
        $existing = CaseSheetResolver::existingRecordId($resource, $taskInstance->id);

        return $existing
            ? redirect()->route("{$resource}.edit", $existing)
            : redirect()->route("{$resource}.create", ['task_instances_id' => $taskInstance->id]);
    }

    /**
     * The optional pre-instance case-sheet draft (2026-08-28) — lets a
     * doctor start filling in clinical notes for a not-yet-started slot,
     * without creating a real `TaskInstance` (which would require going
     * through `TaskStarter::start()`'s mandatory patient-screening gate).
     * Doctor-only: this button only ever appears on the doctor's own
     * "لم تبدأ بعد" rows, never on a staff-facing screen.
     */
    public function openForTask(Task $task): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();
        abort_unless($doctor, 403);

        $resource = CaseSheetResolver::resourceForTask($task);
        CaseSheetReturn::remember();
        $existing = CaseSheetResolver::existingDraftRecordId($resource, $doctor->id, $task->id);

        return $existing
            ? redirect()->route("{$resource}.edit", $existing)
            : redirect()->route("{$resource}.create", ['task_id' => $task->id]);
    }
}
