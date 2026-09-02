<?php

namespace App\Support;

use App\Models\TaskInstance;

/**
 * Which of each case-sheet resource's own real column names holds the
 * patient's name/phone/age/sex/address/occupation — the server-side
 * mirror of `resources/js/Pages/Specialty/SectionedForm.vue`'s
 * `PATIENT_FIELD_MAP` / `flutter_app/lib/features/case_sheet_forms/
 * domain/case_sheet_patient_field_map.dart`'s `kCaseSheetPatientFieldMap`.
 * A third copy of the same small static map, deliberately — same
 * reasoning those two already documented for duplicating it rather than
 * inventing a shared endpoint: it's static, small, and per-resource.
 *
 * Used for the one thing those two don't cover: auto-filling a case
 * sheet's patient fields when it's created for a task instance that
 * already has a patient (2026-09-02, by request — "عند بدء مهمة من قبل
 * المشرف ومسح كيوار المريض يتم ملئ معلومات المريض الى الكيس شيت بصورة
 * تلقائية"). Every `TaskInstance` reaching this has one:
 * `TaskStarter::start()` requires a `PatientRegistration` to start a task
 * at all, so a doctor opening a brand-new sheet for an already-started
 * task never has to re-scan the same patient's registration QR by hand
 * the way the existing manual "مسح رمز المريض" feature (`_scanPatient`/
 * `scanPatient`) still does for the "browse my records, no task"
 * standalone case, where there's no task instance to resolve a patient
 * from at all.
 *
 * `advanced-periodontal-charts` has no entry, matching
 * `kCaseSheetPatientFieldMap`'s own scope — it has no patient-identity
 * fields of its own to fill.
 */
class CaseSheetPatientFieldMap
{
    private const MAP = [
        'dental-charts' => [
            'name' => 'patient_id', 'phone' => 'patient_phone', 'age' => 'patient_age',
            'sex' => 'patient_sex', 'address' => 'patient_address', 'occupation' => 'patient_occupation',
        ],
        'oral-medicine-charts' => [
            'name' => 'patient_id', 'phone' => 'patient_phone', 'age' => 'patient_age',
            'sex' => 'patient_sex', 'address' => 'patient_address', 'occupation' => 'patient_occupation',
        ],
        'surgeries' => [
            'name' => 'patient_name', 'phone' => 'patient_phone', 'age' => 'patient_age',
            'sex' => 'patient_gender', 'address' => 'patient_address', 'occupation' => 'patient_occupation',
        ],
        'periodontal-charts' => [
            'name' => 'patient_name', 'phone' => 'patient_phone', 'age' => 'patient_age',
            'sex' => 'patient_gender', 'address' => 'patient_address', 'occupation' => 'patient_occupation',
        ],
        'prosthodontics-records' => [
            'name' => 'patient_name', 'phone' => 'telephone', 'age' => 'age',
            'sex' => 'sex', 'address' => 'address', 'occupation' => 'occupation',
        ],
        'complete-denture-records' => [
            'name' => 'patient_name', 'phone' => 'telephone', 'age' => 'age',
            'sex' => 'sex', 'address' => 'address', 'occupation' => 'occupation',
        ],
        'orthodontics-records' => [
            'name' => 'patient_name', 'phone' => 'patient_phone', 'age' => 'patient_age',
            'sex' => 'patient_sex', 'address' => 'patient_address',
        ],
        // Grouped — `patient_data` is a JSON-blob column (see
        // `App\Support\PreventionForm`), so this maps into its subkeys
        // instead of real top-level columns. `prefillFor()` below nests
        // these under the group key rather than flattening them.
        'prevention-records' => [
            'group' => 'patient_data',
            'name' => 'child_name', 'phone' => 'phone_number', 'age' => 'patient_age', 'sex' => 'patient_gender',
        ],
    ];

    /**
     * Empty when: this resource has no map entry, the task instance has no
     * linked patient (shouldn't happen for anything that went through
     * `TaskStarter`, but a defensive default costs nothing), or the
     * registration itself has nothing set for every mapped field.
     */
    public static function prefillFor(string $resource, ?TaskInstance $taskInstance): array
    {
        $map = self::MAP[$resource] ?? null;
        $registration = $taskInstance?->patientRegistration;

        if (! $map || ! $registration) {
            return [];
        }

        $source = [
            'name' => $registration->name,
            'phone' => $registration->phone,
            'age' => $registration->age,
            'sex' => $registration->sex,
            'address' => $registration->address,
            'occupation' => $registration->occupation,
        ];

        $group = $map['group'] ?? null;
        $values = [];
        foreach ($map as $field => $column) {
            if ($field === 'group') {
                continue;
            }
            if (filled($source[$field] ?? null)) {
                $values[$column] = (string) $source[$field];
            }
        }

        if ($values === []) {
            return [];
        }

        return $group ? [$group => $values] : $values;
    }
}
