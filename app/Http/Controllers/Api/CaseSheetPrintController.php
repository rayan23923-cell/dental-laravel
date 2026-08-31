<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Services\PermissionManager;
use App\Support\CaseSheetPrint;
use App\Support\CaseSheetPrintRenderer;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;

/**
 * JSON mirror of the printable case sheets, for the Flutter client.
 *
 * Returns the *rendered document model* — letterhead, sections already
 * resolved to label/value pairs, tooth grids, stage rows — rather than the
 * raw record, so the mobile app lays out the same document without having to
 * reimplement the formatting rules (option labels, Yes/No, date trimming)
 * that App\Support\CaseSheetPrintRenderer applies for the web printout.
 */
class CaseSheetPrintController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json([
            'data' => collect(CaseSheetPrint::SHEETS)
                ->map(fn ($config, $resource) => [
                    'resource' => $resource,
                    'title' => $config['title'],
                    'department' => $config['department'] ?? $config['headerDepartment'] ?? null,
                ])
                ->values(),
        ]);
    }

    public function show(string $resource, int $record): JsonResponse
    {
        $config = CaseSheetPrint::config($resource);

        abort_unless($config, 404, 'Unknown case sheet type.');

        /** @var Model $model */
        $model = $config['model'];
        $sheet = $model::findOrFail($record);

        $this->authorizeSheet($sheet);

        $formClass = $config['form'];
        // See CaseSheetPrintRenderer::deriveGroupColumns() — derived from
        // the fields' own `group` keys, not a `groupColumns()` static most
        // `*Form` classes never implemented (real bug: Orthodontics/
        // Prevention printed their grouped fields blank).
        $groupColumns = CaseSheetPrintRenderer::deriveGroupColumns($formClass::sections());
        $stages = method_exists($formClass, 'stages') ? $formClass::stages() : [];
        $chartGroups = method_exists($formClass, 'chartGroups') ? $formClass::chartGroups() : [];
        $chartData = $chartGroups && $sheet->chart_data
            ? json_decode((string) $sheet->chart_data, true)
            : null;

        $settings = ClinicSetting::current();

        // Which fields (if any) print as a circled-tooth-number marker
        // chart instead of a plain comma list — see
        // CaseSheetPrintRenderer::toothMarkerCharts()'s doc comment.
        $excludeKeys = collect($config['toothMarkerCharts'] ?? [])
            ->flatMap(fn ($c) => array_filter([$c['key'], $c['fallbackKey'] ?? null]))
            ->all();

        return response()->json([
            'header' => [
                'university_name' => $settings->university_name ?: 'University of Baghdad',
                'college_name' => $settings->college_name ?: 'College of Dentistry',
                'department' => $config['department'] ?? null,
                'header_department' => $config['headerDepartment'] ?? null,
                'clinic_logo_url' => $settings->logoUrl(),
                'university_logo_url' => $settings->universityLogoUrl(),
            ],
            'title' => $config['title'],
            'doctor_name' => $sheet->doctor_id ? Doctor::whereKey($sheet->doctor_id)->value('name') : null,
            // Identification-strip fallbacks the web printout also uses
            // (`$sheet->student_name`/`$sheet->grade_group` directly) —
            // only a few of the 8 sheet types have these columns, hence the
            // `?? null` rather than assuming every model has them.
            'student_name' => $sheet->student_name ?? null,
            'grade_group' => $sheet->grade_group ?? null,
            'printed_at' => now()->toDateString(),
            'sections' => CaseSheetPrintRenderer::sections($formClass::sections(), $sheet, $groupColumns, $excludeKeys),
            'charts' => CaseSheetPrintRenderer::charts($chartGroups, $chartData),
            // Added alongside the Flutter print feature (2026-08-30) — the
            // web controller has always included this; the JSON mirror
            // simply hadn't needed it until a client actually rendered the
            // odontogram block.
            'dental_chart' => CaseSheetPrintRenderer::dentalChart($formClass::sections(), $sheet),
            'tooth_marker_charts' => CaseSheetPrintRenderer::toothMarkerCharts($config, $sheet),
            'stages' => CaseSheetPrintRenderer::stages($stages, $sheet),
        ]);
    }

    /** Same rule as the web printout — see its controller. */
    private function authorizeSheet(Model $sheet): void
    {
        $principal = Auth::user();

        if ($principal instanceof Doctor) {
            abort_unless((int) $sheet->doctor_id === $principal->id, 403);

            return;
        }

        abort_unless($principal && (new PermissionManager($principal))->can('task_progress', 'open_case_sheet'), 403);
    }
}
