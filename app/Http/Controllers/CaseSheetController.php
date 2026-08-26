<?php

namespace App\Http\Controllers;

use App\Models\TaskInstance;
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
 */
class CaseSheetController extends Controller
{
    /**
     * type_code → route name of this app's equivalent sheet.
     *
     * `partial_denture` intentionally points at the prosthodontics sheet:
     * the original's own switch routes both `partial_denture` and
     * `prosthodontics` to prosthodontics.php. `pediatric` has no sheet in
     * this rebuild (the original's pediatric.php is a 311-line stub with no
     * table behind it), so it falls through to the default.
     */
    private const ROUTES = [
        'operative' => 'dental-charts',
        'partial_denture' => 'prosthodontics-records',
        'prosthodontics' => 'prosthodontics-records',
        'complete_denture' => 'complete-denture-records',
        'surgery' => 'surgeries',
        'periodontal' => 'periodontal-charts',
        'orthodontics' => 'orthodontics-records',
        'prevention' => 'prevention-records',
        'oral_medicine' => 'oral-medicine-charts',
    ];

    public function open(TaskInstance $taskInstance): RedirectResponse
    {
        $doctor = Auth::guard('doctor')->user();

        if ($doctor) {
            // A doctor may only open their own instance.
            abort_unless($taskInstance->doctor_id === $doctor->id, 403);
        } else {
            $user = Auth::user();
            abort_unless($user && (new \App\Services\PermissionManager($user))->can('task_progress', 'open_case_sheet'), 403);
        }

        $taskInstance->load('task.caseSheetType');
        $typeCode = $taskInstance->task?->caseSheetType?->type_code;

        // The original defaults to the operative sheet for an unknown or
        // missing type rather than erroring.
        $resource = self::ROUTES[$typeCode] ?? 'dental-charts';

        // Reuse the sheet already filled for this instance if there is one,
        // otherwise open a blank sheet pre-linked to it — this is what makes
        // the sheet belong to the task rather than float free.
        $existing = $this->existingRecordId($resource, $taskInstance->id);

        return $existing
            ? redirect()->route("{$resource}.edit", $existing)
            : redirect()->route("{$resource}.create", ['task_instances_id' => $taskInstance->id]);
    }

    private function existingRecordId(string $resource, int $taskInstanceId): ?int
    {
        $model = [
            'dental-charts' => \App\Models\DentalChart::class,
            'prosthodontics-records' => \App\Models\ProsthodonticsRecord::class,
            'complete-denture-records' => \App\Models\CompleteDentureRecord::class,
            'surgeries' => \App\Models\Surgery::class,
            'periodontal-charts' => \App\Models\PeriodontalChart::class,
            'orthodontics-records' => \App\Models\OrthodonticsRecord::class,
            'prevention-records' => \App\Models\PreventionRecord::class,
            'oral-medicine-charts' => \App\Models\OralMedicineChart::class,
        ][$resource] ?? null;

        return $model
            ? $model::where('task_instances_id', $taskInstanceId)->value('id')
            : null;
    }
}
