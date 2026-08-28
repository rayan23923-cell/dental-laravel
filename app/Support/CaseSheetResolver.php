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
        $typeCode = $taskInstance->task?->caseSheetType?->type_code;

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
}
