<?php

namespace App\Support;

/**
 * Real section/field layout of dental_clinics2/doctor/oral_medicine.php.
 *
 * Rebuilt (2026-08-21) after the first version was found to have guessed
 * the shape of several JSON-blob columns instead of reading them — most
 * visibly, `past_medical_history` was treated as a single plain textarea,
 * so its real value (a 14-category `{value: yes|no, details: string}`
 * checklist) rendered as a raw JSON dump in a text box. Every field below
 * was checked against both the original's own markup (field names, option
 * values, which columns are grouped vs which are one opaque blob) *and*
 * real imported `oral_medicine_charts` rows, not assumed from either alone.
 *
 * None of this sheet's JSON columns carry an Eloquent cast (see
 * App\Models\OralMedicineChart::casts()) — unlike the operative sheet's
 * `tooth_data`/`endodontics_data`, they're plain text columns. The simpler
 * ones (scalar subkeys only: `jaws_teeth_relations`, `investigations_diagnosis`,
 * `student_visits`) use the generic `group` mechanism SectionedForm.vue
 * already has (posts as `column[subkey]`, reassembled into one JSON string
 * on submit). The rest have genuinely nested/array-valued subkeys a flat
 * group can't express, so each is one field bound to the whole column,
 * with its own dedicated component and manual JSON (de)serialisation —
 * the same pattern `chart_data` (the periodontal sheet) already uses.
 *
 * `extraoral_intraoral_examination.head_diagrams` — the four head
 * pain-location diagrams (frontal/posterior/right/left) — is built (see
 * Components/HeadDiagramsBoard.vue, added 2026-08-20): the original never
 * actually freehand-draws there, it's click-to-place one point per click,
 * stamped with the selected pain-quality symbol from a fixed 10-option
 * list. The reference images themselves (`dental_clinics2/uploads/
 * {front,back,right,left}.jpg`) were copied into `public/images/
 * head-diagrams/` and the point-to-symbol mapping was ported pixel-for-pixel
 * from the original's `drawPainPatternForHeadDiagram()`.
 *
 * **Still deliberately not built**: `clinical_examination.pain_pattern`
 * (a *different*, genuinely freehand canvas — no click-to-place option
 * list, and `clinical_examination` has no non-canvas field at all in the
 * original) and drawn (canvas) signatures elsewhere in the app. Both remain
 * out of scope — see README.
 */
class OralMedicineForm
{
    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'case_no', 'label' => 'Case No.', 'type' => 'text'],
                    ['key' => 'visit_date', 'label' => 'Date', 'type' => 'date', 'required' => true],
                    ['key' => 'patient_id', 'label' => 'Patient Name', 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'patient_phone', 'label' => 'Phone Number', 'type' => 'text'],
                    ['key' => 'patient_age', 'label' => 'Age', 'type' => 'number'],
                    ['key' => 'patient_sex', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['key' => 'patient_address', 'label' => 'Address', 'type' => 'text'],
                    ['key' => 'patient_occupation', 'label' => 'Occupation', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Chief Complaint',
                'fields' => [
                    ['key' => 'chief_complaint', 'label' => 'Chief complaint', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'History of the Complaint',
                'fields' => [
                    // The 28-item symptom checklist plus the seven
                    // open-ended questions, both posted under
                    // history_of_complaint[...] — one component, one field,
                    // see Components/HistoryOfComplaintSection.vue.
                    ['key' => 'history_of_complaint', 'label' => 'History of the Complaint', 'type' => 'history_complaint', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'PMH. (Past Medical History)',
                'note' => 'Mark Yes for anything that applies, and specify details.',
                'fields' => [
                    ['key' => 'past_medical_history', 'label' => 'Past Medical History', 'type' => 'pmh_checklist', 'width' => 'full', 'options' => [
                        ['key' => 'cardiovascular', 'label' => 'Cardiovascular Diseases (Murmurs, Angina, Infarction, Pacemakers & ↓↑ BP)'],
                        ['key' => 'blood', 'label' => "Blood Diseases & Anemia's"],
                        ['key' => 'bone_spinal', 'label' => 'Bone & Spinal disease (Backache, Discs, Osteoporosis)'],
                        ['key' => 'joint', 'label' => 'Joint Diseases (Degenerative or Osteoarthritis, Rheumatoid Arthritis)'],
                        ['key' => 'ent_respiratory', 'label' => 'ENT & Respiratory Diseases (Ear Problems, tonsillitis, Nasal allergies, Sinusitis & Asthma)'],
                        ['key' => 'git', 'label' => 'GIT Diseases (Acid Reflux, Ulcers & Cancer)'],
                        ['key' => 'neurologic', 'label' => "Neurologic Disease (Neuralgias, Trimmers, Stroke, Epilepsy, Parkinson's)"],
                        ['key' => 'psychiatric', 'label' => 'Psychiatric Diseases (Anxiety, Depression, Insomnia & Sleep Apnea)'],
                        ['key' => 'dermatologic', 'label' => "Dermatologic & Autoimmune Disorders (Schleroderma, Multiple sclerosis, Behcet's, Sjogren's …)"],
                        ['key' => 'genitourinary', 'label' => 'Genitourinary Diseases'],
                        ['key' => 'endocrine', 'label' => 'Endocrine (Diabetes, Adrenal, Thyroid) Diseases'],
                        ['key' => 'allergy', 'label' => 'Allergy (Medicine, food)'],
                        ['key' => 'hospitalizations', 'label' => 'Hospitalizations & Pregnancy'],
                        ['key' => 'medications', 'label' => 'Current Medications'],
                    ]],
                ],
            ],
            [
                'title' => 'History of Surgical Operations or Treatments',
                'fields' => [
                    ['key' => 'surgical_history', 'label' => 'Surgical History', 'type' => 'surgical_history', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Family History',
                'fields' => [
                    ['key' => 'family_history', 'label' => 'Family History', 'type' => 'family_history', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Social History',
                'fields' => [
                    ['key' => 'social_history', 'label' => 'Social History', 'type' => 'social_history', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Extraoral / Intraoral Examination',
                'fields' => [
                    ['key' => 'extraoral_intraoral_examination', 'label' => 'Extraoral / Intraoral Examination', 'type' => 'extraoral_exam', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Teeth',
                'fields' => [
                    ['key' => 'present_teeth', 'label' => 'Present teeth', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'teeth_requiring_treatment', 'label' => 'Teeth requiring treatment', 'type' => 'teeth', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Jaws & Teeth Relations',
                'fields' => [
                    // Values are 'class1'/'class2'/'class3' (no underscore)
                    // — confirmed against real imported data; the previous
                    // version used 'class_i'/'class_ii'/'class_iii', which
                    // never matched a stored value.
                    ['group' => 'jaws_teeth_relations', 'key' => 'classification', 'label' => 'Classification', 'type' => 'select', 'options' => [
                        ['value' => 'class1', 'label' => 'Class I'],
                        ['value' => 'class2', 'label' => 'Class II'],
                        ['value' => 'class3', 'label' => 'Class III'],
                    ]],
                    ['group' => 'jaws_teeth_relations', 'key' => 'notes', 'label' => 'Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Investigations, Diagnosis, and Treatment Plan',
                'fields' => [
                    ['group' => 'investigations_diagnosis', 'key' => 'investigations', 'label' => 'Investigations', 'type' => 'textarea', 'width' => 'full'],
                    ['group' => 'investigations_diagnosis', 'key' => 'diagnosis', 'label' => 'Diagnosis', 'type' => 'textarea', 'width' => 'full'],
                    ['group' => 'investigations_diagnosis', 'key' => 'treatment_plan', 'label' => 'Treatment plan', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Student Visits',
                'note' => 'Only the first visit\'s fields are ported (student name, date, staff sign-off as text); the original\'s multi-visit extension and drawn signatures are not built.',
                'fields' => [
                    ['group' => 'student_visits', 'key' => 'student_name', 'label' => 'Student name', 'type' => 'text'],
                    ['group' => 'student_visits', 'key' => 'staff_signature', 'label' => 'Staff signature', 'type' => 'text'],
                    ['group' => 'student_visits', 'key' => 'date', 'label' => 'Date', 'type' => 'date'],
                ],
            ],
            [
                // Real columns, distinct from 'Student Visits' staff_signature
                // above (a subkey inside the student_visits JSON blob) — see
                // App\Support\CaseSheetSupervisorFields. Added (2026-08-28)
                // specifically for the supervisor-preview feature; this sheet
                // had no equivalent field of its own.
                'title' => 'Supervisor',
                'fields' => [
                    ['key' => 'supervisor_notes', 'label' => 'Supervisor Notes', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'supervisor_signature', 'label' => 'Supervisor Signature', 'type' => 'text', 'width' => 'half'],
                ],
            ],
        ];
    }

    /** JSON-blob columns whose subkeys are all scalar — flattened via the generic `group` mechanism. */
    public static function groupColumns(): array
    {
        return ['jaws_teeth_relations', 'investigations_diagnosis', 'student_visits'];
    }
}
