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
 *
 * Every section below Patient Information was merged in from
 * `PeriodontalChartForm::sections()` verbatim (2026-09-03, by request —
 * "اضافة الحقول من periodontal chart الى ادفانسد ماعدا الجدول
 * والمخططات السنية"): Patient Information itself stays this resource's
 * own (first/last name split + DOB + exam-type is deliberate, not a gap),
 * and neither `PeriodontalChartForm::chartGroups()` (the BOP/PPD/CAL
 * table — "الجدول") nor any tooth/odontogram field ("المخططات السنية")
 * is pulled in — this resource's own 32-tooth grid above is exactly what
 * that exclusion means. The old plain "Notes & Approval" section is gone,
 * folded into the merged-in Clinical Examination (`notes`) and Treatment
 * Plan & Approval (`senior_signature`) sections instead of duplicating
 * those two columns in two places.
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
                    // Added alongside the Women Only merge below (2026-09-03)
                    // — that section only shows for a female patient
                    // (SectionedForm.vue's `isFemale` reads
                    // `patient_gender`/`sex`), and nothing else in this
                    // form previously captured gender at all.
                    ['key' => 'patient_gender', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['key' => 'chart_date', 'label' => 'Chart Date', 'type' => 'date', 'required' => true],
                    ['key' => 'exam_type', 'label' => 'Examination Type', 'type' => 'radio', 'options' => [
                        ['value' => 'initial', 'label' => 'Initial Examination'],
                        ['value' => 're_evaluation', 'label' => 'Re-evaluation'],
                    ]],
                ],
            ],
            [
                'title' => 'Women Only',
                'femaleOnly' => true,
                'fields' => [
                    ['key' => 'women_pregnancy', 'label' => 'Pregnancy', 'type' => 'radio', 'options' => PeriodontalChartForm::YND],
                    ['key' => 'pregnancy_weeks', 'label' => 'Number of weeks', 'type' => 'number', 'showWhen' => ['field' => 'women_pregnancy', 'value' => 'yes']],
                    ['key' => 'women_birth_control', 'label' => 'Taking birth control pills or hormonal replacement', 'type' => 'radio', 'options' => PeriodontalChartForm::YND],
                    ['key' => 'women_nursing', 'label' => 'Nursing', 'type' => 'radio', 'options' => PeriodontalChartForm::YND],
                ],
            ],
            [
                'title' => 'Chief Complaint & Medical History',
                'fields' => [
                    ['key' => 'img_chief_complaint', 'label' => 'Chief complaint(s)', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'img_medical_history', 'label' => 'MH', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'History',
                'fields' => [
                    ['key' => 'img_smoker_yes', 'label' => 'Smoker — Yes', 'type' => 'boolean'],
                    ['key' => 'img_smoker_no', 'label' => 'Smoker — No', 'type' => 'boolean'],
                    ['key' => 'img_smoker_prev', 'label' => 'Smoker — Previous', 'type' => 'boolean'],
                    ['key' => 'img_smoker_stopped', 'label' => 'When stopped?', 'type' => 'text'],

                    ['key' => 'img_diabetes_yes', 'label' => 'Diabetes mellitus — Yes', 'type' => 'boolean'],
                    ['key' => 'img_diabetes_no', 'label' => 'Diabetes mellitus — No', 'type' => 'boolean'],
                    ['key' => 'img_diabetes_controlled_yes', 'label' => 'Controlled — Yes', 'type' => 'boolean'],
                    ['key' => 'img_diabetes_controlled_no', 'label' => 'Controlled — No', 'type' => 'boolean'],
                    ['key' => 'img_diabetes_lab', 'label' => 'Lab investigation', 'type' => 'text'],

                    ['key' => 'img_brushing_once', 'label' => 'Brushing — Once/day', 'type' => 'boolean'],
                    ['key' => 'img_brushing_twice', 'label' => 'Brushing — Twice/day', 'type' => 'boolean'],
                    ['key' => 'img_brushing_three', 'label' => 'Brushing — Three/day', 'type' => 'boolean'],
                    ['key' => 'img_brushing_manual', 'label' => 'Manual brush', 'type' => 'boolean'],
                    ['key' => 'img_brushing_powered', 'label' => 'Powered brush', 'type' => 'boolean'],

                    ['key' => 'img_interproximal_yes', 'label' => 'Interproximal aids — Yes', 'type' => 'boolean'],
                    ['key' => 'img_interproximal_no', 'label' => 'Interproximal aids — No', 'type' => 'boolean'],
                    ['key' => 'img_interproximal_type', 'label' => 'Type & frequency', 'type' => 'text'],

                    ['key' => 'img_fam_hist_yes', 'label' => 'Family history of periodontal disease — Yes', 'type' => 'boolean'],
                    ['key' => 'img_fam_hist_no', 'label' => 'Family history of periodontal disease — No', 'type' => 'boolean'],
                    ['key' => 'img_fam_hist_details', 'label' => 'Details', 'type' => 'textarea', 'width' => 'full'],

                    ['key' => 'img_prev_treatment', 'label' => 'Previous treatment by GDP', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Examination',
                'fields' => [
                    ['key' => 'img_tmj_yes', 'label' => 'E/O: TMJ click — Yes', 'type' => 'boolean'],
                    ['key' => 'img_tmj_no', 'label' => 'E/O: TMJ click — No', 'type' => 'boolean'],
                    ['key' => 'img_facial_yes', 'label' => 'Facial asymmetry — Yes', 'type' => 'boolean'],
                    ['key' => 'img_facial_no', 'label' => 'Facial asymmetry — No', 'type' => 'boolean'],
                    ['key' => 'img_facial_details', 'label' => 'Facial asymmetry details', 'type' => 'textarea', 'width' => 'full'],

                    ['key' => 'img_missing_teeth', 'label' => 'Missing teeth', 'type' => 'text'],
                    ['key' => 'img_soft_tissue_yes', 'label' => 'Soft tissue lesion — Yes', 'type' => 'boolean'],
                    ['key' => 'img_soft_tissue_no', 'label' => 'Soft tissue lesion — No', 'type' => 'boolean'],
                    ['key' => 'img_soft_tissue_comments', 'label' => 'Soft tissue comments', 'type' => 'textarea', 'width' => 'full'],

                    ['key' => 'img_occlusal_yes', 'label' => 'Occlusal trauma — Yes', 'type' => 'boolean'],
                    ['key' => 'img_occlusal_no', 'label' => 'Occlusal trauma — No', 'type' => 'boolean'],
                    ['key' => 'img_mobile_yes', 'label' => 'Mobile teeth — Yes', 'type' => 'boolean'],
                    ['key' => 'img_mobile_no', 'label' => 'Mobile teeth — No', 'type' => 'boolean'],
                    ['key' => 'img_mobile_teeth', 'label' => 'Which teeth are mobile', 'type' => 'text'],
                    ['key' => 'img_caries_yes', 'label' => 'Caries — Yes', 'type' => 'boolean'],
                    ['key' => 'img_caries_no', 'label' => 'Caries — No', 'type' => 'boolean'],
                    ['key' => 'img_caries_teeth', 'label' => 'Which teeth are carious', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'BPE (Basic Periodontal Examination)',
                'note' => 'Sextant scores.',
                'fields' => [
                    ['key' => 'exam_bpe_ur', 'label' => 'Upper Right', 'type' => 'text'],
                    ['key' => 'exam_bpe_ua', 'label' => 'Upper Anterior', 'type' => 'text'],
                    ['key' => 'exam_bpe_ul', 'label' => 'Upper Left', 'type' => 'text'],
                    ['key' => 'exam_bpe_lr', 'label' => 'Lower Right', 'type' => 'text'],
                    ['key' => 'exam_bpe_la', 'label' => 'Lower Anterior', 'type' => 'text'],
                    ['key' => 'exam_bpe_ll', 'label' => 'Lower Left', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Radiographs & Investigations',
                'fields' => [
                    ['key' => 'exam_radiograph_periapical', 'label' => 'Periapical', 'type' => 'boolean'],
                    ['key' => 'exam_radiograph_bitewing', 'label' => 'Bitewing', 'type' => 'boolean'],
                    ['key' => 'exam_radiograph_panoramic', 'label' => 'Panoramic (OPG)', 'type' => 'boolean'],
                    ['key' => 'exam_radiograph_cbct', 'label' => 'CBCT', 'type' => 'boolean'],
                    ['key' => 'exam_other_investigations', 'label' => 'Other investigations', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Clinical Examination',
                'fields' => [
                    ['key' => 'oral_hygiene', 'label' => 'Oral Hygiene', 'type' => 'textarea', 'width' => 'half',
                        'help' => 'Plaque, calculus, halitosis, general gingival condition, etc.'],
                    ['key' => 'periodontal_condition', 'label' => 'Periodontal Condition', 'type' => 'textarea', 'width' => 'half',
                        'help' => 'Gingivitis, pockets, bleeding on probing (BOP), recession, mobility, etc.'],
                    ['key' => 'notes', 'label' => 'Additional Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Diagnosis',
                'fields' => [
                    ['key' => 'diagnosis_pattern', 'label' => 'Pattern', 'type' => 'select', 'options' => [
                        ['value' => 'localized', 'label' => 'Localized'],
                        ['value' => 'generalized', 'label' => 'Generalized'],
                        ['value' => 'molar-incisor', 'label' => 'Molar/Incisor'],
                    ]],
                    ['key' => 'diagnosis_stage', 'label' => 'Stage', 'type' => 'select', 'options' => [
                        ['value' => 'I', 'label' => 'Stage I'],
                        ['value' => 'II', 'label' => 'Stage II'],
                        ['value' => 'III', 'label' => 'Stage III'],
                        ['value' => 'IV', 'label' => 'Stage IV'],
                    ]],
                    ['key' => 'diagnosis_grade', 'label' => 'Grade', 'type' => 'select', 'options' => [
                        ['value' => 'A', 'label' => 'Grade A'],
                        ['value' => 'B', 'label' => 'Grade B'],
                        ['value' => 'C', 'label' => 'Grade C'],
                    ]],
                    ['key' => 'diagnosis_status', 'label' => 'Status', 'type' => 'select', 'options' => [
                        ['value' => 'stable', 'label' => 'Stable'],
                        ['value' => 'remission', 'label' => 'In remission'],
                        ['value' => 'unstable', 'label' => 'Unstable'],
                    ]],
                    ['key' => 'diagnosis_risk_factors', 'label' => 'Risk factors', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Treatment Plan & Approval',
                'fields' => [
                    ['key' => 'treatment_plan', 'label' => 'Treatment Plan', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'treatment_plan_date', 'label' => 'Treatment Plan Date', 'type' => 'date'],
                    ['key' => 'senior_doctor_name', 'label' => 'Senior Doctor', 'type' => 'text'],
                    ['key' => 'approval_date', 'label' => 'Approval Date', 'type' => 'date'],
                    ['key' => 'senior_signature', 'label' => 'Senior Signature', 'type' => 'signature', 'width' => 'half'],
                    ['key' => 'clinical_notes', 'label' => 'Clinical Notes', 'type' => 'textarea', 'width' => 'full'],
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
