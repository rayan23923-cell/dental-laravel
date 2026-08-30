<?php

namespace App\Support;

/**
 * Real section/field layout of dental_clinics2/doctor/prevention.php.
 *
 * This sheet is structurally unusual: `prevention_records` has **no
 * per-field columns at all** — save_prevention.php packs everything into
 * two JSON columns, `patient_data` and `examination_data`. So every field
 * here carries a `group` (see SectionedForm.vue's grouping support), using
 * the original's own key names inside those two blobs.
 */
class PreventionForm
{
    /** The original's ten dental-behaviour questions, in its order. */
    public const QUESTIONS = [
        'Do you clean your teeth using toothbrush & paste?',
        'Do you use a fluoridated toothbrush?',
        'How many times do you brush your teeth daily? 1 / 2 / ≥3',
        'Do you use different toothpaste?',
        'Do you replace your toothbrush?',
        'Is there a relation between brushing & dental caries?',
        'When do you brush your teeth?',
        'Do you visit the dentist?',
        'What types of food cause dental caries?',
        'What type of food does NOT cause dental caries?',
    ];

    public static function sections(): array
    {
        return [
            [
                'title' => 'Patient Information',
                'fields' => [
                    ['group' => 'patient_data', 'key' => 'child_name', 'label' => "Child's Name", 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['group' => 'patient_data', 'key' => 'phone_number', 'label' => 'Phone Number', 'type' => 'text'],
                    // 'date'/'patient_group' removed (2026-08-29, by
                    // request): 'date' is set automatically at creation
                    // instead (today's date — PreventionRecordController::
                    // prepare()/Api\PreventionRecordController::store()),
                    // same "auto, once, at create" convention as
                    // Orthodontics' referral_date; 'patient_group' had no
                    // equivalent automatic source, so it's simply gone.
                    ['group' => 'patient_data', 'key' => 'patient_age', 'label' => 'Age', 'type' => 'text'],
                    ['group' => 'patient_data', 'key' => 'patient_gender', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['group' => 'patient_data', 'key' => 'visit', 'label' => 'Visit', 'type' => 'select', 'options' => [
                        ['value' => 'first', 'label' => 'First'],
                        ['value' => 'recall', 'label' => 'Recall'],
                    ]],
                ],
            ],
            [
                'title' => 'Chief Complaint',
                'fields' => [
                    ['group' => 'patient_data', 'key' => 'chief_complaint', 'label' => 'Chief complaint', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Medical History',
                'fields' => [
                    ['group' => 'patient_data', 'key' => 'medical_history', 'label' => 'Relevant medical history, allergies, medications…', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'Dental Behavior and Knowledge',
                'note' => 'The original records these as yes/no (question 2 also allows "I don\'t know").',
                'fields' => static::questionFields(),
            ],
            [
                'title' => 'Treatment Plan',
                'fields' => [
                    ['group' => 'patient_data', 'key' => 'treatment_plan', 'label' => 'Treatment plan', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'DMFS / dmfs Indices',
                'note' => 'Uppercase = permanent dentition, lowercase = primary — the original\'s own convention.',
                'fields' => [
                    ['group' => 'dmfs_indices', 'key' => 'DS', 'label' => 'DS', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'MS', 'label' => 'MS', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'FS', 'label' => 'FS', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'DMFS', 'label' => 'DMFS', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'DMFT', 'label' => 'DMFT', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'ds', 'label' => 'ds', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'ms', 'label' => 'ms', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'fs', 'label' => 'fs', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'dmfs', 'label' => 'dmfs', 'type' => 'text'],
                    ['group' => 'dmfs_indices', 'key' => 'dmft', 'label' => 'dmft', 'type' => 'text'],
                ],
            ],
            [
                'title' => '24-Hour Dietary Recall',
                'fields' => [
                    ['group' => 'dietary_recall', 'key' => 'breakfast', 'label' => 'Breakfast', 'type' => 'text', 'width' => 'half'],
                    ['group' => 'dietary_recall', 'key' => 'after_breakfast', 'label' => 'After breakfast', 'type' => 'text', 'width' => 'half'],
                    ['group' => 'dietary_recall', 'key' => 'lunch', 'label' => 'Lunch', 'type' => 'text', 'width' => 'half'],
                    ['group' => 'dietary_recall', 'key' => 'after_lunch', 'label' => 'After lunch', 'type' => 'text', 'width' => 'half'],
                    ['group' => 'dietary_recall', 'key' => 'dinner', 'label' => 'Dinner', 'type' => 'text', 'width' => 'half'],
                    ['group' => 'dietary_recall', 'key' => 'after_dinner', 'label' => 'After dinner', 'type' => 'text', 'width' => 'half'],
                    ['group' => 'dietary_recall', 'key' => 'bedtime', 'label' => 'Bedtime', 'type' => 'text', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'Nutritional Assessment',
                'fields' => [
                    // 'nutritional_patient_name'/'nutritional_age'/
                    // 'nutritional_class' removed (2026-08-29, by request
                    // — "ازل patient name age class لانها مكررة", remove
                    // them, they're duplicated): each duplicated a field
                    // already collected above in Patient Information
                    // (child_name/patient_age — this section's own `help`
                    // text even said as much: "the original defaults this
                    // to the child's name when left blank"). No auto-fill
                    // added in their place, matching every other
                    // duplicate-field removal this session that wasn't
                    // explicitly asked to become automatic.
                    // 'nutritional_gender' stays — not mentioned in that
                    // request. 'nutritional_group' was also kept then
                    // ("not mentioned in this request") but removed now
                    // in a follow-up, global "ازل group من كل الكيس شيت"
                    // (remove Group from every case sheet) request.
                    ['group' => 'patient_data', 'key' => 'nutritional_gender', 'label' => 'Gender', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'Male'],
                        ['value' => 'female', 'label' => 'Female'],
                    ]],
                    ['group' => 'patient_data', 'key' => 'height', 'label' => 'Height', 'type' => 'text'],
                    ['group' => 'patient_data', 'key' => 'weight', 'label' => 'Weight', 'type' => 'text'],
                    ['group' => 'patient_data', 'key' => 'bmi', 'label' => 'BMI', 'type' => 'text'],
                    ['group' => 'patient_data', 'key' => 'weight_status', 'label' => 'Weight status', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'Signature',
                'fields' => [
                    // 'text' → 'signature' (2026-08-30, by request) — see
                    // App\Support\CaseSheetSignatures. This resource has no
                    // separate `senior_signature` column, so `senior_name`
                    // itself plays that role.
                    ['group' => 'patient_data', 'key' => 'senior_name', 'label' => 'Senior name', 'type' => 'signature'],
                    ['group' => 'patient_data', 'key' => 'signature_date', 'label' => 'Date', 'type' => 'date'],
                ],
            ],
            [
                // Real columns, not part of the patient_data blob like
                // 'Signature' above — see App\Support\CaseSheetSupervisorFields.
                // Added (2026-08-28) specifically for the supervisor-preview
                // feature; this sheet had no equivalent field of its own.
                'title' => 'Supervisor',
                'fields' => [
                    ['key' => 'supervisor_notes', 'label' => 'Supervisor Notes', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'supervisor_signature', 'label' => 'Supervisor Signature', 'type' => 'signature', 'width' => 'half'],
                ],
            ],
        ];
    }

    private static function questionFields(): array
    {
        $fields = [];
        foreach (static::QUESTIONS as $index => $question) {
            $options = [
                ['value' => 'yes', 'label' => 'Yes'],
                ['value' => 'no', 'label' => 'No'],
            ];
            // Only question 2 offers "I don't know" in the original.
            if ($index === 1) {
                $options[] = ['value' => 'idk', 'label' => "I don't know"];
            }

            $fields[] = [
                'group' => 'questions',
                'key' => (string) $index,
                'label' => ($index + 1).'. '.$question,
                'type' => 'radio',
                'options' => $options,
                'width' => 'full',
            ];
        }

        return $fields;
    }

    /**
     * `questions`, `dmfs_indices` and `dietary_recall` are nested *inside*
     * `examination_data` in the original's payload, not top-level columns —
     * the controller re-nests them after the form posts them flat.
     */
    public static function examinationGroups(): array
    {
        return ['questions', 'dmfs_indices', 'dietary_recall'];
    }
}
