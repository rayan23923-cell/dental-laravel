<?php

namespace App\Support;

/**
 * Operative / المخطط السني — the case sheet behind the `operative` type
 * code, stored in `dental_charts`. Port of
 * dental_clinics2/doctor/operative.php (+ dental_chart.php).
 *
 * This is the sheet the earlier port was missing as a *case sheet*: the
 * table and a tooth picker existed, but as a standalone generic form rather
 * than the sectioned clinical sheet the original opens from a task.
 */
class OperativeForm
{
    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    // `dental_charts.patient_id` is a varchar holding the
                    // patient's *name* in the original, not an FK.
                    ['key' => 'patient_id', 'label' => "Patient's Name", 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'patient_phone', 'label' => 'Phone Number', 'type' => 'text'],
                    ['key' => 'visit_date', 'label' => 'Visit Date', 'type' => 'date'],
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
                'title' => 'Chief Complaint & History',
                'fields' => [
                    ['key' => 'chief_complaint', 'label' => 'Chief Complaint', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'history_of_complaint', 'label' => 'History of Present Illness', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Clinical Examination',
                'fields' => [
                    ['key' => 'oral_hygiene', 'label' => 'Oral Hygiene', 'type' => 'textarea', 'width' => 'half'],
                    ['key' => 'periodontal_condition', 'label' => 'Periodontal Condition', 'type' => 'textarea', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Odontogram',
                'note' => 'Tap any tooth to record its condition and the status of each surface.',
                'fields' => [
                    // The real per-tooth odontogram — 32 teeth, five
                    // surfaces each (or three root canals once a tooth is
                    // marked non_vital), colour-coded exactly as the
                    // original's operative.php. See Components/
                    // ToothOdontogram.vue for the full status/colour
                    // vocabulary, read directly from the original's own CSS
                    // and JS rather than guessed.
                    ['key' => 'tooth_data', 'label' => 'Odontogram', 'type' => 'dental_chart', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Quick Lists',
                'note' => 'Select teeth from the grid for each condition — a text summary alongside the odontogram above.',
                'fields' => [
                    ['key' => 'non_vital_teeth', 'label' => 'Non-vital Teeth', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'missing_teeth', 'label' => 'Missing Teeth', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'crown_bridge_teeth', 'label' => 'Crowns / Bridges', 'type' => 'teeth', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Endodontic Treatment',
                'fields' => [
                    // The whole Endodontics card, including its iOS-style
                    // enable toggle — see Components/EndodonticsSection.vue
                    // for the field-by-field port and what's deliberately
                    // not included (image galleries, a drawn signature).
                    ['key' => 'endodontics_data', 'label' => 'Endodontic Treatment', 'type' => 'endodontics', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Treatment Plan & Approval',
                'fields' => [
                    ['key' => 'treatment_plan_notes', 'label' => 'Treatment Plan Notes', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'treatment_plan_date', 'label' => 'Treatment Plan Date', 'type' => 'date'],
                    ['key' => 'senior_doctor_name', 'label' => 'Supervising Doctor', 'type' => 'text'],
                    // 'text' → 'signature' (2026-08-30, by request) — see
                    // App\Support\CaseSheetSignatures: no longer a
                    // free-typed name, auto-captured (signer + timestamp)
                    // server-side when the supervisor taps "توقيع".
                    ['key' => 'senior_signature', 'label' => 'Supervisor Signature', 'type' => 'signature', 'width' => 'half'],
                    ['key' => 'notes', 'label' => 'Additional Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }
}
