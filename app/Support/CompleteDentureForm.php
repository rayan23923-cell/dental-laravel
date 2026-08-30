<?php

namespace App\Support;

/**
 * Real section/field layout of dental_clinics2/doctor/complete_denture.php.
 * Labels (including the original's numbered "1- …" prefixes and its
 * bilingual patient-info captions) and placeholder hints are the original's.
 */
class CompleteDentureForm
{
    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'patient_name', 'label' => "اسم المريض (Patient's Name)", 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'telephone', 'label' => 'الهاتف (Phone Number)', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'age', 'label' => 'العمر (Age)', 'type' => 'number'],
                    ['key' => 'sex', 'label' => 'الجنس (Gender)', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'ذكر (Male)'],
                        ['value' => 'female', 'label' => 'أنثى (Female)'],
                    ]],
                    ['key' => 'address', 'label' => 'العنوان (Address)', 'type' => 'text'],
                    ['key' => 'occupation', 'label' => 'العمل (Occupation)', 'type' => 'text'],
                ],
            ],
            // 'student_name'/'group_name' removed (2026-08-29, by request
            // — "ازل group من كل الكيس شيت وازل كذلك student name"):
            // redundant with the doctor's own identity, same reasoning as
            // every other resource's student-info removal this session.
            [
                'title' => 'Student / Case',
                'fields' => [
                    ['key' => 'first_time', 'label' => 'First time?', 'type' => 'select', 'options' => [
                        ['value' => 'yes', 'label' => 'Yes'],
                        ['value' => 'no', 'label' => 'No'],
                    ]],
                ],
            ],
            [
                'title' => 'Medical history',
                'fields' => [
                    ['key' => 'medical_history', 'label' => 'Document systemic diseases, medications, allergies, and any relevant medical notes.', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Dental History',
                'fields' => [
                    ['key' => 'dental_extraction_reason', 'label' => '1- Reason for tooth extraction.', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'last_tooth_extracted_teeth', 'label' => '2- Select the teeth that were most recently extracted', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'last_tooth_extracted', 'label' => 'Last tooth extracted (notes)', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'dentist_visit_regular', 'label' => 'Regular dentist visits?', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'complete_denture_reason', 'label' => '3- Reasons for constructing a denture.', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'partial_denture_reason', 'label' => 'Reasons for a partial denture', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'previous_complete_denture', 'label' => '4- Any previous complete denture?', 'type' => 'text', 'width' => 'half', 'help' => 'Yes/No + details'],
                    ['key' => 'previous_partial_denture', 'label' => 'Any previous partial denture?', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'not_using_reason', 'label' => 'Reason for not using it', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'new_denture_reason', 'label' => 'a) Why do you want to make a new denture?', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'b) Regarding the old denture how is?',
                'fields' => [
                    ['key' => 'old_denture_retention', 'label' => '1) Retention', 'type' => 'text'],
                    ['key' => 'old_denture_stability', 'label' => '2) Stability', 'type' => 'text'],
                    ['key' => 'old_denture_centric', 'label' => '3) Centric', 'type' => 'text'],
                    ['key' => 'old_denture_vertical', 'label' => '4) Vertical', 'type' => 'text'],
                    ['key' => 'old_denture_appearance', 'label' => '5) Appearance', 'type' => 'text'],
                    ['key' => 'old_denture_comfort', 'label' => '6) Comfort', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Examination — A: Extraoral',
                'fields' => [
                    ['key' => 'facial_muscle_tone', 'label' => '1- Facial muscle tone', 'type' => 'text', 'width' => 'half', 'help' => 'Normal / Hypotonic / Hypertonic'],
                    ['key' => 'face_form', 'label' => '2- Face form', 'type' => 'text', 'width' => 'half', 'help' => 'Square / Ovoid / Tapering'],
                    ['key' => 'angles_jaw_classification', 'label' => "3- Angle's jaw classification", 'type' => 'text', 'width' => 'half', 'help' => 'Class I / II / III'],
                    ['key' => 'vertical_dimensions_rest', 'label' => '4- Vertical dimensions of rest', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'tmj_disorder', 'label' => 'TMJ disorder', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'muscles_mastication', 'label' => 'Muscles of mastication', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'facial_tissue', 'label' => 'Facial tissue', 'type' => 'text', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Examination — B: Intraoral',
                'fields' => [
                    ['key' => 'ridge_form_upper', 'label' => '1- Ridge form — Upper', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'ridge_form_lower', 'label' => '1- Ridge form — Lower', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'mucosa_upper', 'label' => '2- Mucosa — Upper', 'type' => 'text', 'width' => 'half', 'help' => 'Firm / flabby / inflamed…'],
                    ['key' => 'mucosa_lower', 'label' => '2- Mucosa — Lower', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'palate_depth', 'label' => '3- Palate depth', 'type' => 'text', 'help' => 'Shallow / Medium / Deep'],
                    ['key' => 'tongue_size', 'label' => '4- Tongue size', 'type' => 'text', 'help' => 'Small / Average / Large'],
                    ['key' => 'bony_exostosis', 'label' => '5- Presence of any bony exostosis', 'type' => 'text', 'help' => 'Describe location / size'],
                    ['key' => 'teeth_to_extract', 'label' => 'Teeth to be extracted', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'missing_teeth', 'label' => 'Missing teeth', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'soft_tissue_condition', 'label' => 'Soft tissue condition', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'abnormal_lesion', 'label' => 'Abnormal lesion', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'abutments_mobility', 'label' => 'Abutments mobility', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'preprosthetic_treatment', 'label' => 'Preprosthetic treatment', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Diagnosis and starting',
                'fields' => [
                    ['key' => 'diagnosis_starting', 'label' => 'Diagnosis and starting', 'type' => 'textarea', 'width' => 'full'],
                    // 'text' → 'signature' (2026-08-30, by request) — see
                    // App\Support\CaseSheetSignatures.
                    ['key' => 'diagnosis_instructor_signature', 'label' => 'Signature of instructor', 'type' => 'signature', 'width' => 'half',
                        'help' => 'Instructor name/signature reference.'],
                ],
            ],
        ];
    }

    /**
     * "Stages and evaluation" — the original renders this as a table with a
     * signature / date / grade column per stage. Stage labels and the column
     * key prefixes are the original's (`stage_{key}_signature|date|grade`).
     */
    public static function stages(): array
    {
        return [
            ['key' => 'preliminary', 'label' => 'Preliminary impression', 'note' => 'a. Upper — b. Lower'],
            ['key' => 'surveying', 'label' => 'Cast - Surveying'],
            ['key' => 'final', 'label' => 'Final impression', 'note' => 'a. Upper — b. Lower'],
            ['key' => 'jawrel', 'label' => 'Registration of jaw relation'],
            ['key' => 'trial', 'label' => 'Trial denture'],
            ['key' => 'flasking', 'label' => 'Ready for flasking'],
            ['key' => 'cd', 'label' => 'C.D in mouth (Complete Denture)'],
            ['key' => 'adjust1', 'label' => '1st adjustment'],
            ['key' => 'finaleval', 'label' => 'Final evaluation'],
        ];
    }
}
