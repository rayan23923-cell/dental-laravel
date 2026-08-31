<?php

namespace App\Support;

/**
 * "Advanced Periodontal Chart" (2026-08-31, by request) — a brand-new
 * case-sheet type modeled functionally on periodontalchart-online.com's
 * own charting tool (patient info + Initial/Re-evaluation toggle + a
 * 32-tooth, 6-site-per-tooth probing grid: Mobility/Implant/Furcation/
 * BOP/Plaque/Gingival Margin/Probing Depth/Attachment Level). Unlike every
 * other *Form class in this app, this one has no original PHP page to
 * port from — see the matching migration's own doc comment.
 *
 * The big per-tooth grid isn't part of `sections()` at all (same reason
 * `chartGroups()`/Plaque Index live outside `sections()` for
 * periodontal-charts): it's rendered by `AdvancedPerioChart.vue` /
 * `AdvancedPerioChartField` (Flutter) directly against the `chart_data`
 * JSON column, gated by the `advancedPerioChart` schema flag rather than
 * a field entry here.
 */
class AdvancedPeriodontalChartForm
{
    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'patient_last_name', 'label' => 'Patient Last Name', 'type' => 'text', 'required' => true],
                    ['key' => 'patient_first_name', 'label' => 'First Name', 'type' => 'text', 'required' => true],
                    ['key' => 'patient_dob', 'label' => 'Date of Birth', 'type' => 'date'],
                    ['key' => 'chart_date', 'label' => 'Chart Date', 'type' => 'date', 'required' => true],
                    ['key' => 'exam_type', 'label' => 'Examination Type', 'type' => 'radio', 'options' => [
                        ['value' => 'initial', 'label' => 'Initial Examination'],
                        ['value' => 're_evaluation', 'label' => 'Re-evaluation'],
                    ]],
                ],
            ],
            [
                'title' => 'Notes & Approval',
                'fields' => [
                    ['key' => 'notes', 'label' => 'Notes', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'senior_signature', 'label' => 'Senior Signature', 'type' => 'signature', 'width' => 'half'],
                ],
            ],
        ];
    }

    /** Every column the sections above actually bind to. */
    public static function keys(): array
    {
        return collect(static::sections())
            ->flatMap(fn ($section) => collect($section['fields'])->pluck('key'))
            ->all();
    }
}
