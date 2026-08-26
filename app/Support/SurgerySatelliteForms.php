<?php

namespace App\Support;

/**
 * Layouts for the four small satellite tables around the main case sheets.
 * None of these is a standalone case sheet in the original — they're the
 * repeating rows attached to a parent record (a surgery, a dental chart, a
 * tooth treatment), so each leads with a picker for that parent instead of
 * a doctor selector.
 */
class SurgerySatelliteForms
{
    public static function followUp(): array
    {
        return [
            [
                'title' => 'Follow-up',
                'fields' => [
                    ['key' => 'surgery_id', 'label' => 'Surgery', 'type' => 'lookup', 'required' => true, 'width' => 'half'],
                    ['key' => 'follow_up_date', 'label' => 'Follow-up date', 'type' => 'date'],
                    ['key' => 'patient_status', 'label' => 'Patient status', 'type' => 'text'],
                    ['key' => 'next_appointment', 'label' => 'Next appointment', 'type' => 'date'],
                    ['key' => 'findings', 'label' => 'Findings', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'notes', 'label' => 'Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }

    public static function image(): array
    {
        return [
            [
                'title' => 'Surgery Image',
                'fields' => [
                    ['key' => 'surgery_id', 'label' => 'Surgery', 'type' => 'lookup', 'required' => true, 'width' => 'half'],
                    // The enum's three stages, straight from the column.
                    ['key' => 'image_type', 'label' => 'Stage', 'type' => 'select', 'required' => true, 'options' => [
                        ['value' => 'preop', 'label' => 'Pre-operative'],
                        ['value' => 'intraop', 'label' => 'Intra-operative'],
                        ['value' => 'postop', 'label' => 'Post-operative'],
                    ]],
                    ['key' => 'image_path', 'label' => 'Image', 'type' => 'file', 'width' => 'half'],
                    ['key' => 'description', 'label' => 'Description', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }

    public static function medication(): array
    {
        return [
            [
                'title' => 'Medication',
                'fields' => [
                    ['key' => 'surgery_id', 'label' => 'Surgery', 'type' => 'lookup', 'required' => true, 'width' => 'half'],
                    ['key' => 'medication_name', 'label' => 'Medication', 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'dosage', 'label' => 'Dosage', 'type' => 'text'],
                    ['key' => 'frequency', 'label' => 'Frequency', 'type' => 'text'],
                    ['key' => 'duration', 'label' => 'Duration', 'type' => 'text'],
                    ['key' => 'notes', 'label' => 'Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }

    public static function treatmentPlan(): array
    {
        return [
            [
                'title' => 'Treatment Plan',
                'fields' => [
                    ['key' => 'chart_id', 'label' => 'Dental chart', 'type' => 'lookup', 'required' => true, 'width' => 'half'],
                    ['key' => 'plan_date', 'label' => 'Plan date', 'type' => 'date'],
                    ['key' => 'mark', 'label' => 'Mark', 'type' => 'text'],
                    ['key' => 'doctor_name', 'label' => 'Doctor name', 'type' => 'text'],
                    ['key' => 'plan_notes', 'label' => 'Plan notes', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'signature', 'label' => 'Signature', 'type' => 'text', 'width' => 'half'],
                ],
            ],
        ];
    }

    public static function treatmentMaterial(): array
    {
        return [
            [
                'title' => 'Treatment Material',
                'fields' => [
                    ['key' => 'tooth_treatment_id', 'label' => 'Tooth treatment', 'type' => 'lookup', 'required' => true, 'width' => 'half'],
                    ['key' => 'material_name', 'label' => 'Material', 'type' => 'text', 'required' => true, 'width' => 'half'],
                    // The enum's six kinds, straight from the column.
                    ['key' => 'material_type', 'label' => 'Type', 'type' => 'select', 'options' => [
                        ['value' => 'filling', 'label' => 'Filling'],
                        ['value' => 'crown', 'label' => 'Crown'],
                        ['value' => 'bridge', 'label' => 'Bridge'],
                        ['value' => 'implant', 'label' => 'Implant'],
                        ['value' => 'cement', 'label' => 'Cement'],
                        ['value' => 'other', 'label' => 'Other'],
                    ]],
                    ['key' => 'quantity', 'label' => 'Quantity', 'type' => 'decimal'],
                    ['key' => 'unit', 'label' => 'Unit', 'type' => 'text'],
                    ['key' => 'cost', 'label' => 'Cost', 'type' => 'decimal'],
                    ['key' => 'notes', 'label' => 'Notes', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }
}
