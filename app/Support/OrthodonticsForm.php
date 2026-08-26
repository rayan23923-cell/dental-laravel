<?php

namespace App\Support;

/**
 * Real section/field layout of dental_clinics2/doctor/orthodontics.php,
 * cross-checked field-for-field against the original's markup (3,100 lines)
 * and, for the assembled shape, save_orthodontics.php's own `$examination_data`
 * array (the ground truth for keys and types — not the page's JS, which
 * carries some dead collectors for a `position[]`/`others[]` that no longer
 * have matching inputs anywhere in the form and always save as `[]`; not
 * reproduced here for the same reason the original never populates them).
 *
 * Rebuilt (2026-08-20) after the first pass mapped nearly every clinical
 * field to a plain 'text' input regardless of its real control, and was
 * missing three real widgets outright:
 * - `teeth_squares` — the "Number of Teeth" 4-row × 16-column marking grid
 *   (Unerupted/Erupted/Erupted/Unerupted; each cell opens a picker for
 *   primary A–E, permanent 1–8, or the "/" extracted mark). Renders as
 *   Components/TeethSquaresGrid.vue.
 * - `treatment_stages` and `appliance_designs` — repeating
 *   `{index: {info, quadrants}}` rows, each row an info line plus the
 *   original's `fdi-cross` quadrant tooth picker. Both render as
 *   Components/QuadrantRepeater.vue (same shape, different label).
 * - Several fields the first pass had as free text are real quadrant tooth
 *   pickers in the original (`badly_carious`, `supplementary_teeth`,
 *   `overlapped_teeth`, `inclined_teeth`), and several radios had the
 *   wrong option set (`angles_classification`/`canine_classification`/
 *   `incisors_classification` are `class1`/`class2`/`class3` — no
 *   Div-1/Div-2 variants; the previous CLASS_OPTIONS invented those).
 *
 * The patient/referral half has real columns and binds directly; the
 * clinical half has none — save_orthodontics.php packs it all into one
 * `examination_data` JSON blob, keyed exactly as it writes them. Fields
 * carrying `'group' => 'examination_data'` are keys inside that blob.
 *
 * `appliance_type` is a legacy fallback the original auto-derives from the
 * first `appliance_designs` row only when loading pre-migration records
 * that predate the repeater — not an independently editable field, so it
 * isn't one here either.
 *
 * Deliberately not built: the per-row canvas signature pad on the separate
 * `treatment_plans` satellite table (Treatment Plan & Senior Approval) —
 * same class of simplification as every other sheet's drawn signatures
 * (plain text field instead, see App\Support\SurgerySatelliteForms). The
 * department-role gate the original applies to `diagnosis`/`treatment_plan`/
 * `treatment_stages`/`appliance_designs` (editable only by admins or a
 * doctor with a role in the owning department) isn't replicated either —
 * this port's readonly is the same all-or-nothing CaseSheetAccess gate
 * every other sheet uses.
 */
class OrthodonticsForm
{
    private const CLASS_OPTIONS = [
        ['value' => 'class1', 'label' => 'Class I'],
        ['value' => 'class2', 'label' => 'Class II'],
        ['value' => 'class3', 'label' => 'Class III'],
    ];

    public static function sections(): array
    {
        $g = 'examination_data';

        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'patient_name', 'label' => 'Patient Name', 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'patient_phone', 'label' => 'Phone Number', 'type' => 'text'],
                    ['key' => 'patient_age', 'label' => 'Age', 'type' => 'number'],
                    ['key' => 'patient_sex', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['key' => 'patient_address', 'label' => 'Address', 'type' => 'text', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Student / Referral',
                'fields' => [
                    ['key' => 'student_name', 'label' => 'Student Name', 'type' => 'text'],
                    ['key' => 'group_name', 'label' => 'Group', 'type' => 'text'],
                    ['key' => 'supervised_by', 'label' => 'Supervised by', 'type' => 'text'],
                    ['key' => 'referral_date', 'label' => 'Referral Date', 'type' => 'date'],
                    ['key' => 'referred_from', 'label' => 'Referred from', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Chief Complaint',
                'fields' => [
                    ['group' => $g, 'key' => 'chief_complaint', 'label' => 'Chief Complain', 'type' => 'checkboxes', 'width' => 'full', 'options' => [
                        ['value' => 'esthetic', 'label' => 'Esthetic'],
                        ['value' => 'functional', 'label' => 'Functional'],
                        ['value' => 'phonetic', 'label' => 'Phonetic'],
                        ['value' => 'others', 'label' => 'Others'],
                    ]],
                    ['group' => $g, 'key' => 'chief_complaint_others', 'label' => 'Others — specify', 'type' => 'text', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Clinical Examination — Skeletal Factors',
                'fields' => [
                    ['group' => $g, 'key' => 'examined', 'label' => 'Examined', 'type' => 'text', 'width' => 'half'],
                    ['group' => $g, 'key' => 'examined_methods', 'label' => 'Evaluation Method', 'type' => 'checkboxes', 'width' => 'half', 'options' => [
                        ['value' => 'radiographically', 'label' => 'Radiographically'],
                        ['value' => 'clinically', 'label' => 'Clinically'],
                    ]],
                    ['group' => $g, 'key' => 'ap_relation_radio', 'label' => 'A-P Relation — Radiographically', 'type' => 'checkboxes', 'options' => self::CLASS_OPTIONS],
                    ['group' => $g, 'key' => 'ap_relation_clinical', 'label' => 'A-P Relation — Clinically', 'type' => 'checkboxes', 'options' => self::CLASS_OPTIONS],
                    ['group' => $g, 'key' => 'vertical_relation', 'label' => 'Vertical Relation', 'type' => 'radio', 'options' => [
                        ['value' => 'normal', 'label' => 'Normal'],
                        ['value' => 'increased', 'label' => 'Increased'],
                        ['value' => 'decreased', 'label' => 'Decreased'],
                    ]],
                    ['group' => $g, 'key' => 'horizontal_relation', 'label' => 'Horizontal Relation', 'type' => 'radio', 'options' => [
                        ['value' => 'symmetrical', 'label' => 'Symmetrical'],
                        ['value' => 'asymmetrical', 'label' => 'Asymmetrical'],
                    ]],
                    ['group' => $g, 'key' => 'deviation_side', 'label' => 'Deviation Side', 'type' => 'checkboxes', 'options' => [
                        ['value' => 'r', 'label' => 'Right'],
                        ['value' => 'l', 'label' => 'Left'],
                    ]],
                ],
            ],
            [
                'title' => 'Clinical Examination — Soft Tissue',
                'fields' => [
                    ['group' => $g, 'key' => 'facial_profile', 'label' => 'Facial Profile', 'type' => 'radio', 'options' => [
                        ['value' => 'straight', 'label' => 'Straight'],
                        ['value' => 'convex', 'label' => 'Convex'],
                        ['value' => 'concave', 'label' => 'Concave'],
                    ]],
                    ['group' => $g, 'key' => 'tongue_size', 'label' => 'Tongue Size', 'type' => 'radio', 'options' => [
                        ['value' => 'normal', 'label' => 'Normal'],
                        ['value' => 'small', 'label' => 'Small'],
                        ['value' => 'big', 'label' => 'Big'],
                    ]],
                    ['group' => $g, 'key' => 'lips_posture', 'label' => 'Lips Posture', 'type' => 'radio', 'options' => [
                        ['value' => 'competent', 'label' => 'Competent'],
                        ['value' => 'incompetent', 'label' => 'Incompetent'],
                        ['value' => 'potentially_competent', 'label' => 'Potentially competent'],
                    ]],
                    ['group' => $g, 'key' => 'lip_line', 'label' => 'Lip Line', 'type' => 'radio', 'options' => [
                        ['value' => 'high', 'label' => 'High'],
                        ['value' => 'low', 'label' => 'Low'],
                        ['value' => 'normal', 'label' => 'Normal'],
                    ]],
                ],
            ],
            [
                'title' => 'Dental Local Factors',
                'fields' => [
                    ['group' => $g, 'key' => 'teeth_arch_proportion', 'label' => 'Teeth / Arch Proportion', 'type' => 'radio', 'options' => [
                        ['value' => 'normal', 'label' => 'Normal'],
                        ['value' => 'crowding', 'label' => 'Crowding'],
                        ['value' => 'spacing', 'label' => 'Spacing'],
                    ]],
                    ['group' => $g, 'key' => 'teeth_arch_proportion_other', 'label' => 'Other', 'type' => 'text'],
                    ['group' => $g, 'key' => 'angles_classification', 'label' => "Angle's Classification", 'type' => 'radio', 'options' => self::CLASS_OPTIONS],
                    ['group' => $g, 'key' => 'canine_classification', 'label' => 'Canine Classification', 'type' => 'radio', 'options' => self::CLASS_OPTIONS],
                    ['group' => $g, 'key' => 'canine_classification_r', 'label' => 'Canine — Right', 'type' => 'text'],
                    ['group' => $g, 'key' => 'canine_classification_l', 'label' => 'Canine — Left', 'type' => 'text'],
                    ['group' => $g, 'key' => 'incisors_classification', 'label' => 'Incisors Classification', 'type' => 'radio', 'options' => self::CLASS_OPTIONS],
                    ['group' => $g, 'key' => 'incisors_classification_r', 'label' => 'Incisors — Right', 'type' => 'text'],
                    ['group' => $g, 'key' => 'incisors_classification_l', 'label' => 'Incisors — Left', 'type' => 'text'],
                    ['group' => $g, 'key' => 'over_jet', 'label' => 'Over Jet (mm)', 'type' => 'decimal'],
                    ['group' => $g, 'key' => 'over_bite', 'label' => 'Over Bite (mm)', 'type' => 'decimal'],
                    ['group' => $g, 'key' => 'cross_bite', 'label' => 'Cross Bite', 'type' => 'checkboxes', 'width' => 'full', 'options' => [
                        ['value' => 'single_tooth', 'label' => 'Single tooth'],
                        ['value' => 'group_of_teeth', 'label' => 'Group of teeth'],
                        ['value' => 'anterior', 'label' => 'Anterior'],
                        ['value' => 'posterior', 'label' => 'Posterior'],
                        ['value' => 'bilateral', 'label' => 'Bilateral'],
                        ['value' => 'scissor_bite', 'label' => 'Scissor bite'],
                    ]],
                    ['group' => $g, 'key' => 'cross_bite_other', 'label' => 'Cross bite — other', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Number of Teeth',
                'fields' => [
                    ['group' => $g, 'key' => 'teeth_squares', 'label' => 'Number of teeth (mark each square)', 'type' => 'teeth_squares_grid', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Other Dental Conditions',
                'fields' => [
                    ['group' => $g, 'key' => 'congenital_missing', 'label' => 'Congenital missing teeth', 'type' => 'teeth', 'width' => 'half'],
                    ['group' => $g, 'key' => 'extracted_teeth', 'label' => 'Extracted teeth', 'type' => 'teeth', 'width' => 'half'],
                    ['group' => $g, 'key' => 'badly_carious', 'label' => 'Badly carious teeth', 'type' => 'teeth', 'width' => 'half'],
                    ['group' => $g, 'key' => 'impacted_teeth', 'label' => 'Impacted teeth', 'type' => 'teeth', 'width' => 'half'],
                    ['group' => $g, 'key' => 'form', 'label' => 'Form', 'type' => 'checkboxes', 'width' => 'full', 'options' => [
                        ['value' => 'peg_shape_lateral', 'label' => 'Peg shape lateral incisors'],
                    ]],
                    ['group' => $g, 'key' => 'displacement_teeth', 'label' => 'Position: Displacement', 'type' => 'teeth'],
                    ['group' => $g, 'key' => 'rotation_teeth', 'label' => 'Position: Rotation', 'type' => 'teeth'],
                    ['group' => $g, 'key' => 'submerged_teeth', 'label' => 'Position: Submerged', 'type' => 'teeth'],
                    ['group' => $g, 'key' => 'habits', 'label' => 'Habits', 'type' => 'checkboxes', 'width' => 'full', 'options' => [
                        ['value' => 'digit_sucking', 'label' => 'Digit sucking'],
                        ['value' => 'nail_biting', 'label' => 'Nail biting'],
                        ['value' => 'bruxism', 'label' => 'Bruxism'],
                        ['value' => 'lip_sucking', 'label' => 'Lip sucking'],
                        ['value' => 'mouth_breathing', 'label' => 'Mouth breathing'],
                        ['value' => 'tongue_thrust', 'label' => 'Tongue thrust'],
                    ]],
                    ['group' => $g, 'key' => 'oral_hygiene', 'label' => 'Oral Hygiene', 'type' => 'radio', 'options' => [
                        ['value' => 'good', 'label' => 'Good'],
                        ['value' => 'fair', 'label' => 'Fair'],
                        ['value' => 'poor', 'label' => 'Poor'],
                    ]],
                    ['group' => $g, 'key' => 'supernumerary', 'label' => 'Supernumerary teeth', 'type' => 'checkboxes', 'options' => [
                        ['value' => 'conical', 'label' => 'Conical'],
                        ['value' => 'tuberculate', 'label' => 'Tuberculate'],
                    ]],
                    ['group' => $g, 'key' => 'supplementary_teeth', 'label' => 'Supernumerary: Supplementary', 'type' => 'teeth', 'width' => 'half'],
                    ['group' => $g, 'key' => 'overlapped_teeth', 'label' => 'Others: Overlapped', 'type' => 'teeth', 'width' => 'half'],
                    ['group' => $g, 'key' => 'inclined_teeth', 'label' => 'Others: Inclined', 'type' => 'teeth', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Diagnosis and Treatment Plan',
                'fields' => [
                    ['group' => $g, 'key' => 'diagnosis', 'label' => 'Diagnosis', 'type' => 'textarea', 'width' => 'full'],
                    ['group' => $g, 'key' => 'treatment_plan', 'label' => 'Treatment plan', 'type' => 'textarea', 'width' => 'full'],
                    ['group' => $g, 'key' => 'treatment_stages', 'label' => 'Stages of treatment', 'type' => 'quadrant_repeater', 'width' => 'full', 'itemLabel' => 'Stage', 'infoLabel' => 'Stage Information'],
                    ['group' => $g, 'key' => 'appliance_designs', 'label' => 'Appliance type & Design', 'type' => 'quadrant_repeater', 'width' => 'full', 'itemLabel' => 'Appliance', 'infoLabel' => 'Appliance Information'],
                ],
            ],
        ];
    }
}
