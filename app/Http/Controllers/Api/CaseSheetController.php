<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CaseSheetType;
use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\PermissionManager;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetResolver;
use App\Support\CaseSheetSupervisorFields;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Flutter's equivalent of the web `CaseSheetController::open()` redirect —
 * same `CaseSheetResolver` lookup, same access rules (a doctor may only
 * open their own instance; staff need `task_progress.open_case_sheet`),
 * but returning JSON instead of a redirect response, since Flutter needs
 * to decide where to navigate rather than follow a server redirect.
 *
 * Auth branching mirrors `TaskInstanceQrController::scan()`: checked in
 * code against `$request->user()`'s type, not via `permission:` route
 * middleware — that middleware assumes a staff `User` principal, which
 * would break the doctor half of this same endpoint.
 */
class CaseSheetController extends Controller
{
    public function open(Request $request, TaskInstance $taskInstance): JsonResponse
    {
        $principal = $request->user();

        if ($principal instanceof Doctor) {
            abort_unless($taskInstance->doctor_id === $principal->id, 403);
        } else {
            abort_unless((new PermissionManager($principal))->can('task_progress', 'open_case_sheet'), 403);
        }

        $resource = CaseSheetResolver::resourceFor($taskInstance);
        $recordId = CaseSheetResolver::existingRecordId($resource, $taskInstance->id);
        $caseSheetType = $taskInstance->task?->caseSheetType;

        return response()->json([
            'resource' => $resource,
            'record_id' => $recordId,
            // Auto-fills the new sheet's patient fields (2026-09-02, by
            // request) from whichever patient TaskStarter::start() already
            // tied this task instance to — see CaseSheetPatientFieldMap's
            // own doc comment. Only meaningful (and only computed) when
            // there's no existing record yet; Flutter merges this into the
            // blank record it seeds `DynamicSectionForm` with on create.
            'patient_prefill' => $recordId === null ? CaseSheetPatientFieldMap::prefillFor($resource, $taskInstance) : [],
            'case_sheet_type' => $caseSheetType ? [
                'id' => $caseSheetType->id,
                'name_ar' => $caseSheetType->name_ar,
                'name_en' => $caseSheetType->name_en,
            ] : null,
            // Staff view but never save (App\Services\CaseSheetAccess) —
            // except these fields, which only staff may edit. A doctor
            // (who owns and can save the rest of the record) always gets
            // an empty list here, matching the web equivalent in each of
            // the 8 resource controllers' form().
            'supervisor_editable_fields' => $principal instanceof Doctor ? [] : CaseSheetSupervisorFields::fieldsFor($resource),
            // Mirrors the web `readonly` prop (`$readonly || CaseSheetAccess
            // ::isViewOnly()`) — Flutter has no server-rendered readonly
            // flag of its own otherwise, so this is the one place it learns
            // whether the current viewer may save at all.
            'readonly' => ! $principal instanceof Doctor,
        ]);
    }

    /**
     * Flutter's equivalent of the web `openForTask()` — same optional
     * pre-instance draft, doctor-only (see that method's doc comment for
     * why: no real `TaskInstance` is created, so no `TaskStarter`/
     * screening-gate involvement).
     */
    public function openForTask(Request $request, Task $task): JsonResponse
    {
        $doctor = $request->user();
        abort_unless($doctor instanceof Doctor, 403);

        $resource = CaseSheetResolver::resourceForTask($task);
        $recordId = CaseSheetResolver::existingDraftRecordId($resource, $doctor->id, $task->id);
        $caseSheetType = $task->caseSheetType;

        return response()->json([
            'resource' => $resource,
            'record_id' => $recordId,
            'case_sheet_type' => $caseSheetType ? [
                'id' => $caseSheetType->id,
                'name_ar' => $caseSheetType->name_ar,
                'name_en' => $caseSheetType->name_en,
            ] : null,
        ]);
    }
}
