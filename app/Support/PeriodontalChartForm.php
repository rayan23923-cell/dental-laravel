<?php

namespace App\Support;

/**
 * The real section/field layout of dental_clinics2/doctor/periodontal_chart.php,
 * replacing the flat auto-generated column list the generic Specialty/Form
 * was driven by. Extracted from the original page's actual markup — section
 * headings, labels, input types and option sets are the original's, not
 * inferred from column names.
 */
class PeriodontalChartForm
{
    /** Yes / No / Don't-know triples, as the original's medical-history tables use. */
    public const YND = [
        ['value' => 'yes', 'label' => 'Yes'],
        ['value' => 'no', 'label' => 'No'],
        ['value' => 'dk', 'label' => "Don't know"],
    ];

    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'patient_name', 'label' => 'Patient Name', 'type' => 'text', 'required' => true],
                    ['key' => 'patient_phone', 'label' => 'Phone Number', 'type' => 'text'],
                    ['key' => 'chart_date', 'label' => 'Date', 'type' => 'date', 'required' => true],
                    ['key' => 'patient_age', 'label' => 'Age', 'type' => 'number'],
                    ['key' => 'patient_gender', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['key' => 'patient_address', 'label' => 'Address', 'type' => 'text'],
                    ['key' => 'patient_occupation', 'label' => 'Occupation', 'type' => 'text'],
                    ['key' => 'patient_marital_status', 'label' => 'Marital Status', 'type' => 'select', 'options' => [
                        ['value' => 'single', 'label' => 'Single'],
                        ['value' => 'married', 'label' => 'Married'],
                    ]],
                ],
            ],
            // "Student / Case" section (Student Name/Group/Case Start
            // Date/Mentor) removed entirely (2026-08-29, by request) —
            // "معلومات الطبيب نفسها معلومات الطالب" (the doctor's info is
            // the same as the student's): the doctor filling this sheet
            // already is the student, and their identity is already the
            // record's `doctor_id`/`Doctor::group` elsewhere, so a
            // separate free-text block only duplicated it. Unlike the
            // matching Orthodontics removal, no auto-fill replacement was
            // requested here — the columns (`student_name`, `student_group`,
            // `case_start_date`, `mentor_name`) still exist and stay
            // nullable, simply no longer collected.
            [
                // Shown only when gender = female, matching the original's
                // #womenOnlySection display toggle.
                'title' => 'Women Only',
                'femaleOnly' => true,
                'fields' => [
                    ['key' => 'women_pregnancy', 'label' => 'Pregnancy', 'type' => 'radio', 'options' => self::YND],
                    ['key' => 'pregnancy_weeks', 'label' => 'Number of weeks', 'type' => 'number', 'showWhen' => ['field' => 'women_pregnancy', 'value' => 'yes']],
                    ['key' => 'women_birth_control', 'label' => 'Taking birth control pills or hormonal replacement', 'type' => 'radio', 'options' => self::YND],
                    ['key' => 'women_nursing', 'label' => 'Nursing', 'type' => 'radio', 'options' => self::YND],
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
                    // Added 2026-08-29 — a real, validated column
                    // (`Api\PeriodontalChartController`'s rules) already
                    // registered as supervisor-only in
                    // `CaseSheetSupervisorFields`. 'text' → 'signature'
                    // (2026-08-30, by request) — see
                    // App\Support\CaseSheetSignatures: auto-captured
                    // (signer + timestamp) instead of a typed name.
                    ['key' => 'senior_signature', 'label' => 'Senior Signature', 'type' => 'signature', 'width' => 'half'],
                    ['key' => 'clinical_notes', 'label' => 'Clinical Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }

    /**
     * The three chart groups the original renders and serialises into
     * `chart_data` (see its collectChartData()): initial visit, post-hygiene
     * re-evaluation (PPD/CAL only — the original has no BOP table there), and
     * follow-up. Key names match the original's JSON exactly so charts saved
     * by either app remain readable by the other.
     */
    public static function chartGroups(): array
    {
        return [
            ['key' => 'perioChart', 'title' => 'Periodontal Chart — Initial', 'tables' => [
                ['key' => 'bop', 'label' => 'BOP', 'type' => 'bop'],
                ['key' => 'ppd', 'label' => 'PPD (mm)', 'type' => 'ppd'],
                ['key' => 'cal', 'label' => 'CAL (mm)', 'type' => 'cal'],
            ]],
            ['key' => 'perioChartPostHygiene', 'title' => 'After Hygiene Phase', 'tables' => [
                ['key' => 'ppd', 'label' => 'PPD (mm)', 'type' => 'ppd'],
                ['key' => 'cal', 'label' => 'CAL (mm)', 'type' => 'cal'],
            ]],
            ['key' => 'perioChartFollowup', 'title' => 'Follow-up', 'tables' => [
                ['key' => 'bop', 'label' => 'BOP', 'type' => 'bop'],
                ['key' => 'ppd', 'label' => 'PPD (mm)', 'type' => 'ppd'],
                ['key' => 'cal', 'label' => 'CAL (mm)', 'type' => 'cal'],
            ]],
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
