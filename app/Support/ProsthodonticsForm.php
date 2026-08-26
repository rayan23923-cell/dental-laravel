<?php

namespace App\Support;

/**
 * Real section/field layout of dental_clinics2/doctor/prosthodontics.php
 * (removable partial denture case sheet). Labels — including the original's
 * lettered "C- …/D- …/E- …" prefixes — are the original's.
 */
class ProsthodonticsForm
{
    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['key' => 'patient_name', 'label' => "Patient's Name", 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'patient_phone', 'label' => 'Phone Number', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'age', 'label' => 'Age', 'type' => 'number'],
                    ['key' => 'sex', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['key' => 'telephone', 'label' => 'Telephone (alt.)', 'type' => 'text'],
                    ['key' => 'occupation', 'label' => 'Occupation', 'type' => 'text'],
                    ['key' => 'address', 'label' => 'Address', 'type' => 'text', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Student / Case',
                'fields' => [
                    ['key' => 'student_name', 'label' => 'Student Name', 'type' => 'text'],
                    ['key' => 'group_name', 'label' => 'Group', 'type' => 'text'],
                    ['key' => 'first_time', 'label' => 'First time?', 'type' => 'select', 'options' => [
                        ['value' => 'yes', 'label' => 'Yes'],
                        ['value' => 'no', 'label' => 'No'],
                    ]],
                ],
            ],
            [
                'title' => 'Medical history',
                'fields' => [
                    ['key' => 'medical_history', 'label' => 'Enter medical history (e.g., allergies, medications, systemic conditions)', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Dental History',
                'fields' => [
                    ['key' => 'dental_extraction_reason', 'label' => 'Reason for tooth extraction', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'dentist_visit_regular', 'label' => 'Regular dentist visits?', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'partial_denture_reason', 'label' => 'Reasons for constructing a partial denture', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'previous_partial_denture', 'label' => 'Any previous partial denture?', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'not_using_reason', 'label' => 'Reason for not using it', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'A- Extraoral Examination',
                'fields' => [
                    ['key' => 'tmj_disorder', 'label' => 'TMJ disorder (clicking)', 'type' => 'select', 'options' => [
                        ['value' => 'No', 'label' => 'No'],
                        ['value' => 'Yes', 'label' => 'Yes'],
                    ]],
                    ['key' => 'muscles_mastication', 'label' => 'Muscles of mastication (tone)', 'type' => 'text', 'help' => 'Normal / Abnormal'],
                    ['key' => 'facial_tissue', 'label' => 'Facial tissue and structure', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'B- Intraoral Examination',
                'fields' => [
                    ['key' => 'missing_teeth', 'label' => 'Missing Teeth — For Partial Denture', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'caries_teeth', 'label' => 'Caries teeth', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'soft_tissue_condition', 'label' => 'C- Condition of soft tissue', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'abnormal_lesion', 'label' => 'D- Presence of any abnormal lesion', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'abutments_mobility', 'label' => 'E- Mobility of abutments', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'teeth_extraction', 'label' => 'F- Teeth to be extracted', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'preprosthetic_treatment', 'label' => 'G- Pre-prosthetic treatment required', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Diagnosis and starting',
                'fields' => [
                    ['key' => 'diagnosis_starting', 'label' => 'Diagnosis and starting', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'diagnosis_instructor_signature', 'label' => 'Signature of instructor', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'diagnosis_date', 'label' => 'Date', 'type' => 'date'],
                    ['key' => 'diagnosis_grade', 'label' => 'Grade/Mark', 'type' => 'text'],
                ],
            ],
        ];
    }

    /**
     * Same nine-row evaluation table as the complete denture sheet except
     * the seventh stage, which is "R.P.D in mouth" here (column prefix
     * `stage_rpd_*`) rather than "C.D in mouth".
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
            ['key' => 'rpd', 'label' => 'R.P.D in mouth'],
            ['key' => 'adjust1', 'label' => '1st adjustment'],
            ['key' => 'finaleval', 'label' => 'Final evaluation'],
        ];
    }
}
