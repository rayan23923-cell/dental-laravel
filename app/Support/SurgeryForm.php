<?php

namespace App\Support;

/**
 * Real section/field layout of dental_clinics2/doctor/surgery.php.
 * Unlike orthodontics/prevention this sheet has proper per-field columns,
 * so everything binds directly. The `mh_*` medical-history block is the
 * original's yes/no checklist.
 */
class SurgeryForm
{
    private const YN = [
        ['value' => 'yes', 'label' => 'Yes'],
        ['value' => 'no', 'label' => 'No'],
    ];

    /** The original's medical-history checklist, in its order. */
    private const MEDICAL_HISTORY = [
        'mh_blood_pressure' => 'Blood pressure',
        'mh_diabetes' => 'Diabetes',
        'mh_heart' => 'Heart disease',
        'mh_thyroid' => 'Thyroid',
        'mh_bleeding' => 'Bleeding disorder',
        'mh_epilepsy' => 'Epilepsy',
        'mh_respiratory' => 'Respiratory',
        'mh_git' => 'GIT',
        'mh_liver' => 'Liver',
        'mh_kidney' => 'Kidney',
        'mh_hiv' => 'HIV',
        'mh_implants' => 'Implants / prosthesis',
        'mh_pregnant' => 'Pregnant',
    ];

    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'patient_name', 'label' => 'Patient Name', 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'patient_phone', 'label' => 'Phone Number', 'type' => 'text'],
                    ['key' => 'patient_age', 'label' => 'Age', 'type' => 'number'],
                    ['key' => 'patient_gender', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['key' => 'patient_address', 'label' => 'Address', 'type' => 'text'],
                    ['key' => 'patient_occupation', 'label' => 'Occupation', 'type' => 'text'],
                ],
            ],
            // 'student_name'/'grade_group'/'surgery_date_field'/'start_time'/
            // 'status'/'staff_signature' removed (2026-08-30, by explicit
            // request — "ازل student name group/grade date start time
            // status staff signature"). Note 'grade_group' was
            // deliberately *kept* the day before (confirmed with the user
            // it's one combined Grade+Group column, and removing it would
            // also drop Grade tracking) — this is a direct, later
            // instruction overriding that earlier call, not a
            // contradiction to reconcile. 'surgery_type' is the only
            // field from this section the user did not name; it stays.
            [
                'title' => 'Case',
                'fields' => [
                    ['key' => 'surgery_type', 'label' => 'Surgery type', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Chief Complaint',
                'fields' => [
                    ['key' => 'chief_complaint', 'label' => 'Chief complaint', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'cc_pain', 'label' => 'Pain', 'type' => 'boolean'],
                    ['key' => 'cc_swelling', 'label' => 'Swelling', 'type' => 'boolean'],
                    ['key' => 'cc_others', 'label' => 'Others', 'type' => 'text', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'History of Present Illness',
                'fields' => [
                    ['key' => 'hpi_duration', 'label' => 'Duration', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'hpi_onset', 'label' => 'Onset', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'hpi_factors', 'label' => 'Aggravating / relieving factors', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'hpi_characteristics', 'label' => 'Characteristics', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'past_dental_history', 'label' => 'Past dental history', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            // Yes/No fields switched from 'select' (a dropdown — tap, wait
            // for the picker, tap "Yes"/"No") to 'radio' (2026-08-30, by
            // request — "حول القائمة المنسدلة الى جيك بوكس للسرعة
            // والسهولة", convert the dropdown to a faster tap-to-select
            // control): both options are already visible inline with one
            // tap to choose, no picker round-trip. Matches this app's own
            // existing convention for a mutually-exclusive Yes/No choice
            // (e.g. Prevention's dental-behaviour questions) — `options`
            // stay exactly `self::YN`, only `type` changes.
            [
                'title' => 'Medical History',
                'fields' => array_merge(
                    array_map(
                        fn ($key, $label) => ['key' => $key, 'label' => $label, 'type' => 'radio', 'options' => self::YN],
                        array_keys(self::MEDICAL_HISTORY),
                        self::MEDICAL_HISTORY
                    ),
                    [
                        ['key' => 'mh_hospitalization', 'label' => 'Previous hospitalization', 'type' => 'radio', 'options' => self::YN],
                        ['key' => 'mh_hospitalization_details', 'label' => 'Hospitalization details', 'type' => 'textarea', 'width' => 'full'],
                        ['key' => 'mh_smoking', 'label' => 'Smoking', 'type' => 'radio', 'options' => self::YN],
                        ['key' => 'mh_smoking_amount', 'label' => 'Smoking amount', 'type' => 'text'],
                        ['key' => 'mh_allergies', 'label' => 'Allergies', 'type' => 'radio', 'options' => self::YN],
                        ['key' => 'mh_allergies_details', 'label' => 'Allergy details', 'type' => 'textarea', 'width' => 'full'],
                        ['key' => 'mh_drugs', 'label' => 'Current medication', 'type' => 'radio', 'options' => self::YN],
                        ['key' => 'mh_drugs_details', 'label' => 'Medication details', 'type' => 'textarea', 'width' => 'full'],
                        ['key' => 'medical_history', 'label' => 'Additional medical notes', 'type' => 'textarea', 'width' => 'full'],
                    ]
                ),
            ],
            [
                'title' => 'Examination & Diagnosis',
                'fields' => [
                    ['key' => 'exam_extraoral', 'label' => 'Extraoral examination', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'exam_intraoral', 'label' => 'Intraoral examination', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'investigation', 'label' => 'Investigation', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'diagnosis', 'label' => 'Diagnosis', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Procedure',
                'fields' => [
                    ['key' => 'selected_teeth', 'label' => 'Selected teeth', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'treatment_tooth', 'label' => 'Treatment tooth', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'surgical_procedure', 'label' => 'Surgical procedure', 'type' => 'textarea', 'width' => 'full'],
                    // 'anesthesia_type'/'duration_minutes' removed
                    // (2026-08-30, by request — "Anesthesia type duration
                    // remove thim").
                    ['key' => 'complications', 'label' => 'Complications', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Post-operative',
                'fields' => [
                    ['key' => 'postop_instructions', 'label' => 'Post-op instructions', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'follow_up_date', 'label' => 'Follow-up date', 'type' => 'date'],
                    ['key' => 'notes', 'label' => 'Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Approval',
                'fields' => [
                    ['key' => 'senior_doctor_name', 'label' => 'Senior doctor', 'type' => 'text'],
                    ['key' => 'approval_date', 'label' => 'Approval date', 'type' => 'date'],
                    ['key' => 'senior_signature', 'label' => 'Senior signature', 'type' => 'text', 'width' => 'half'],
                ],
            ],
        ];
    }
}
