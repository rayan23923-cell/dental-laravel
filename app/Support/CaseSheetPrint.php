<?php

namespace App\Support;

use App\Models\AdvancedPeriodontalChart;
use App\Models\CompleteDentureRecord;
use App\Models\DentalChart;
use App\Models\OralMedicineChart;
use App\Models\OrthodonticsRecord;
use App\Models\PeriodontalChart;
use App\Models\PreventionRecord;
use App\Models\ProsthodonticsRecord;
use App\Models\Surgery;

/**
 * Registry behind the printable case sheets — the Laravel equivalent of the
 * original's `doctor/*_print_html.php` family.
 *
 * The original ships one standalone print page per specialty (nine of them,
 * 34–150 KB each) that re-queries the record and re-lists every field by
 * hand. They all share one design — A4, ~9pt, black hairline borders, grey
 * `section-title` bars, a two-logo letterhead, a department sub-header and a
 * QR back to the sheet — but each restates it, which is why they drifted
 * apart (margins of 5/8/10mm, body text of 9/9.5/10pt, two of the nine
 * missing the QR entirely).
 *
 * Here the design lives once in `resources/views/print/case-sheet.blade.php`
 * and the *content* is driven by the same `App\Support\*Form::sections()`
 * definitions the on-screen sheets already render from. That is the point:
 * a field added to a sheet appears on its printout automatically, which in
 * the original required editing two files that could silently disagree.
 *
 * Each entry carries what the original hard-codes at the top of its print
 * page: the model to load, the layout class, the `<title>`, and the
 * department line under the letterhead — all copied verbatim from the
 * corresponding `*_print_html.php`.
 */
class CaseSheetPrint
{
    /**
     * Keyed by the resource/route prefix already used by the sheets and by
     * CaseSheetController::ROUTES, so a printable sheet is addressable with
     * the same identifier the rest of the app uses.
     *
     * `department` is rendered as the `.sub-header` line, except for oral
     * medicine, where the original folds it into the letterhead itself
     * (`headerDepartment`) instead of printing a separate sub-header.
     */
    public const SHEETS = [
        'dental-charts' => [
            'model' => DentalChart::class,
            'form' => OperativeForm::class,
            'title' => 'Operative Case Sheet',
            // The on-screen edit/create title (DentalChartController::form()) —
            // deliberately not the same string as `title` above, which is
            // the print letterhead's; kept alongside it here so both stay
            // in one registry instead of two independently-drifting ones.
            'formTitle' => 'المخطط السني (Operative)',
            'department' => 'Department of Conservative',
        ],
        'prosthodontics-records' => [
            'model' => ProsthodonticsRecord::class,
            'form' => ProsthodonticsForm::class,
            'title' => 'Partial Denture Case Sheet',
            'formTitle' => 'Prosthodontics Record',
            'department' => 'PROSTHODONTIC',
            // The original (prosthodontics_print_html.php) draws these two
            // as circled-tooth-number grids under a "Dental Chart - Adult
            // Teeth" heading rather than the plain comma list `sections()`
            // would otherwise print for a `teeth`-type field — see
            // CaseSheetPrintRenderer::toothMarkerCharts(). `key` is
            // excluded from the generic section rendering so it isn't
            // printed twice.
            'toothMarkerCharts' => [
                ['key' => 'missing_teeth', 'label' => 'Missing teeth'],
                ['key' => 'caries_teeth', 'label' => 'Carious teeth'],
            ],
        ],
        'complete-denture-records' => [
            'model' => CompleteDentureRecord::class,
            'form' => CompleteDentureForm::class,
            'title' => 'Complete Denture Case Sheet',
            'formTitle' => 'Complete Denture Record',
            'department' => 'PROSTHODONTIC',
            // The original falls back to `last_tooth_extracted_teeth` when
            // `teeth_to_extract` is empty (complete_denture_print_html.php's
            // own `$teethToExtract = $lastToothExtractedTeeth` fallback) —
            // same rule here, via `fallbackKey`. `missing_teeth` is parsed
            // by the original too but never actually rendered anywhere in
            // its own print page (a dead variable there), so it's left as
            // a plain `sections()` cell here rather than invented a grid
            // for it that the original itself doesn't have.
            'toothMarkerCharts' => [
                ['key' => 'teeth_to_extract', 'fallbackKey' => 'last_tooth_extracted_teeth', 'label' => 'Teeth to be extracted'],
            ],
        ],
        'surgeries' => [
            'model' => Surgery::class,
            'form' => SurgeryForm::class,
            'title' => 'Surgical Case Sheet',
            'formTitle' => 'Surgery',
            'department' => 'Department of Oral & Maxillofacial Surgery',
            'toothMarkerCharts' => [
                ['key' => 'selected_teeth', 'label' => 'Dental Chart - Selected Teeth'],
            ],
        ],
        'periodontal-charts' => [
            'model' => PeriodontalChart::class,
            'form' => PeriodontalChartForm::class,
            'title' => 'Periodontal Chart',
            'formTitle' => 'Periodontal Chart',
            'department' => 'Department of Periodontics',
        ],
        // "Advanced Periodontal Chart" (2026-08-31) — registered here so
        // Api\CaseSheetFormController can serve its schema to Flutter (that
        // endpoint is gated on this registry, not just print); the print
        // button this unavoidably also enables only renders this resource's
        // plain `sections()` fields today (patient info/notes), not the
        // 32-tooth grid — that lives entirely in `chart_data`, read only by
        // AdvancedPerioChart.vue/AdvancedPerioChartField directly, with no
        // print-side renderer built yet (not requested this round).
        'advanced-periodontal-charts' => [
            'model' => AdvancedPeriodontalChart::class,
            'form' => AdvancedPeriodontalChartForm::class,
            'title' => 'Advanced Periodontal Chart',
            'formTitle' => 'Advanced Periodontal Chart',
            'department' => 'Department of Periodontics',
        ],
        'orthodontics-records' => [
            'model' => OrthodonticsRecord::class,
            'form' => OrthodonticsForm::class,
            'title' => 'Orthodontics Case Sheet',
            'formTitle' => 'Orthodontics Record',
            'department' => 'Dentistry Department (Orthodontics)',
        ],
        'prevention-records' => [
            'model' => PreventionRecord::class,
            'form' => PreventionForm::class,
            'title' => 'Prevention Case Sheet',
            'formTitle' => 'Prevention Record',
            'department' => 'Department of Preventive Dentistry',
        ],
        'oral-medicine-charts' => [
            'model' => OralMedicineChart::class,
            'form' => OralMedicineForm::class,
            'title' => 'Facial Pain and TMJ Disorders Case Sheet',
            'formTitle' => 'Oral Medicine Chart',
            // The original prints this inside the letterhead block rather
            // than as a sub-header line (oral_medicine_print_html.php:499).
            'department' => null,
            'headerDepartment' => 'Dept. of Oral Diagnosis/Oral Medicine Clinic',
        ],
    ];

    public static function config(string $resource): ?array
    {
        return self::SHEETS[$resource] ?? null;
    }

    public static function exists(string $resource): bool
    {
        return isset(self::SHEETS[$resource]);
    }
}
