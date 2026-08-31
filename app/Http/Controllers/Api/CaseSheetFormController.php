<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\CaseSheetPrint;
use App\Support\CaseSheetPrintRenderer;
use App\Support\CaseSheetSupervisorFields;
use App\Support\PlaqueChart;
use Illuminate\Http\JsonResponse;

/**
 * Exposes each specialty's `App\Support\*Form::sections()` layout as JSON —
 * the same field/section/type/options description
 * `resources/js/Pages/Specialty/SectionedForm.vue` already renders from —
 * so the Flutter client can build one generic dynamic form instead of
 * hand-porting 12 bespoke screens (see flutter_app/README.md §4, "the one
 * architectural decision worth getting right").
 *
 * This is layout metadata only — no record. A record's actual values come
 * from the existing per-resource REST endpoints (`GET /oral-medicine-charts/
 * {id}`, etc.), already built. Fetching the schema once and the record
 * separately mirrors how the web app itself works: `App\Support\*Form`
 * classes are pure layout, `Inertia::render()` bolts a record onto them at
 * request time.
 *
 * Covers the 8 sheets in `CaseSheetPrint::SHEETS` — the main case sheets,
 * not the 5 satellite tables (treatment plans/materials, surgery follow-
 * ups/images/medications), which use a different, simpler prop shape
 * (`hideDoctor`, `lookups`) via `Concerns\RendersSatelliteForm` and aren't
 * in scope for this pass.
 */
class CaseSheetFormController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json([
            'data' => collect(CaseSheetPrint::SHEETS)
                ->map(fn ($config, $resource) => [
                    'resource' => $resource,
                    'title' => $config['formTitle'],
                ])
                ->values(),
        ]);
    }

    public function show(string $resource): JsonResponse
    {
        $config = CaseSheetPrint::config($resource);

        abort_unless($config, 404, 'Unknown case sheet type.');

        $formClass = $config['form'];
        $sections = $formClass::sections();

        // See CaseSheetPrintRenderer::deriveGroupColumns() — scanned from
        // the fields' own `group` keys rather than a `groupColumns()`
        // static most `*Form` classes don't implement.
        $groupColumns = CaseSheetPrintRenderer::deriveGroupColumns($sections);

        $chartGroups = method_exists($formClass, 'chartGroups') ? $formClass::chartGroups() : [];
        $stages = method_exists($formClass, 'stages') ? $formClass::stages() : [];
        // "Advanced Periodontal Chart" (2026-08-31) — a completely separate
        // 32-tooth grid mechanism from `chartGroups` (this resource has
        // none), rendered by AdvancedPerioChart.vue/AdvancedPerioChartField
        // directly against `chart_data`. advanced-periodontal-charts only.
        $advancedPerioChart = $resource === 'advanced-periodontal-charts';

        return response()->json([
            'resource' => $resource,
            'title' => $config['formTitle'],
            'sections' => $sections,
            'groupColumns' => $groupColumns,
            'chartGroups' => $chartGroups,
            // Every sheet that has per-tooth charts stores them in
            // `chart_data` — true for `periodontal-charts` (the sole
            // `chartGroups()` implementer) and now `advanced-periodontal-charts`
            // (no `chartGroups()`, but its own big grid lives in the same
            // column) — same hard-coded column name the print controllers
            // already assume rather than inventing a new per-form "chart
            // column" static for a fact that's been constant across every
            // sheet built so far.
            'chartField' => ($chartGroups || $advancedPerioChart) ? 'chart_data' : null,
            // "Plaque Index" — a completely separate feature from
            // `chartGroups` above despite sharing the same `chart_data`
            // column (see App\Support\PlaqueChart's own doc comment).
            // periodontal-charts only, same gate as chartField.
            'plaqueVisits' => $resource === 'periodontal-charts' ? PlaqueChart::VISITS : [],
            'advancedPerioChart' => $advancedPerioChart,
            'stages' => $stages,
            // The canonical list from App\Support\CaseSheetSupervisorFields
            // — unlike Api\CaseSheetController::open()'s per-viewer
            // `supervisor_editable_fields` (empty for a doctor), this is
            // sent unconditionally, since schema layout is viewer-agnostic.
            // DynamicSectionForm needs both together: this to know a field
            // is supervisor-only at all (so it stays visible but locked for
            // a doctor, never editable — see fieldDisabled()), the other to
            // know whether *this* viewer may actually edit it.
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor($resource),
        ]);
    }
}
