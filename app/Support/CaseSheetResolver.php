<?php

namespace App\Support;

use App\Models\CompleteDentureRecord;
use App\Models\DentalChart;
use App\Models\OralMedicineChart;
use App\Models\OrthodonticsRecord;
use App\Models\PeriodontalChart;
use App\Models\PreventionRecord;
use App\Models\ProsthodonticsRecord;
use App\Models\Surgery;
use App\Models\Task;
use App\Models\TaskInstance;

/**
 * Extracted from `CaseSheetController` (2026-08-27) so both the web
 * controller and the new `Api\CaseSheetController` resolve a task instance
 * to its clinical-form resource the exact same way, instead of two
 * independently-maintained copies of the same `type_code` → resource map.
 */
class CaseSheetResolver
{
    /**
     * type_code → route/resource name of this app's equivalent sheet.
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

    private const MODELS = [
        'dental-charts' => DentalChart::class,
        'prosthodontics-records' => ProsthodonticsRecord::class,
        'complete-denture-records' => CompleteDentureRecord::class,
        'surgeries' => Surgery::class,
        'periodontal-charts' => PeriodontalChart::class,
        'orthodontics-records' => OrthodonticsRecord::class,
        'prevention-records' => PreventionRecord::class,
        'oral-medicine-charts' => OralMedicineChart::class,
    ];

    public static function resourceFor(TaskInstance $taskInstance): string
    {
        $taskInstance->loadMissing('task.caseSheetType');

        return self::resourceForTypeCode($taskInstance->task?->caseSheetType?->type_code);
    }

    /**
     * Same resolution, starting from a bare `Task` instead of a
     * `TaskInstance` — used for the optional pre-instance case-sheet
     * draft a doctor can start filling in before formally starting the
     * task (see `existingDraftRecordId()`), where there's no
     * `TaskInstance` yet to resolve from.
     */
    public static function resourceForTask(Task $task): string
    {
        $task->loadMissing('caseSheetType');

        return self::resourceForTypeCode($task->caseSheetType?->type_code);
    }

    private static function resourceForTypeCode(?string $typeCode): string
    {
        // The original defaults to the operative sheet for an unknown or
        // missing type rather than erroring.
        return self::ROUTES[$typeCode] ?? 'dental-charts';
    }

    public static function existingRecordId(string $resource, int $taskInstanceId): ?int
    {
        $model = self::MODELS[$resource] ?? null;

        return $model
            ? $model::where('task_instances_id', $taskInstanceId)->value('id')
            : null;
    }

    /** The Eloquent model class behind a resource slug — used by `CaseSheetSignatures::allSignedForInstance()`. */
    public static function modelFor(string $resource): ?string
    {
        return self::MODELS[$resource] ?? null;
    }

    /**
     * A doctor+task's optional pre-instance draft, if one exists — see
     * this class's `resourceForTask()` doc comment. `whereNull('task_instances_id')`
     * means a draft that later gets formally linked to a real instance
     * (via the normal `task_instances_id`-keyed path) is no longer found
     * here, so a subsequent tap of the same unstarted-slot button starts
     * a fresh draft rather than reopening the now-linked one.
     */
    public static function existingDraftRecordId(string $resource, int $doctorId, int $taskId): ?int
    {
        $model = self::MODELS[$resource] ?? null;

        return $model
            ? $model::where('doctor_id', $doctorId)->where('task_id', $taskId)->whereNull('task_instances_id')->value('id')
            : null;
    }
}
