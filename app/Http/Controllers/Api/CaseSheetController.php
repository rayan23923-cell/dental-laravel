<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CaseSheetType;
use App\Models\Doctor;
use App\Models\TaskInstance;
use App\Services\PermissionManager;
use App\Support\CaseSheetResolver;
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
            'case_sheet_type' => $caseSheetType ? [
                'id' => $caseSheetType->id,
                'name_ar' => $caseSheetType->name_ar,
                'name_en' => $caseSheetType->name_en,
            ] : null,
        ]);
    }
}
