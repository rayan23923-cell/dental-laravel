<?php

namespace App\Support;

use App\Models\PatientRegistration;
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
 * `advanced-periodontal-charts` (2026-09-04, by request — "اضف كيو ار
 * لمسح معلومات المريض مثل كيسشيتات البقية") is handled separately from
 * the generic `MAP` loop below rather than added to it: it's the only
 * resource that splits the patient's name into two columns
 * (`patient_first_name`/`patient_last_name`) instead of one, so filling
 * it needs an actual name split, not just a field rename — see
 * `advancedPeriodontalPrefill()`.
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
        $registration = $taskInstance?->patientRegistration;

        if (! $registration) {
            return [];
        }

        if ($resource === 'advanced-periodontal-charts') {
            return self::advancedPeriodontalPrefill($registration);
        }

        $map = self::MAP[$resource] ?? null;

        if (! $map) {
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

    /**
     * First word of the registration's name → `patient_first_name`, the
     * rest → `patient_last_name` — the reverse of what
     * `AdvancedPeriodontalChartController::resolvePatientId()` already
     * does when it recombines these two fields back into one name to
     * look up/create the `Patient` row. A single-word name fills only
     * `patient_first_name`, leaving the still-`required` last name for
     * the doctor to fill by hand rather than guessing a split.
     */
    private static function advancedPeriodontalPrefill(PatientRegistration $registration): array
    {
        $values = [];

        if (filled($registration->name)) {
            $parts = preg_split('/\s+/', trim((string) $registration->name), 2);
            $values['patient_first_name'] = $parts[0];
            if (isset($parts[1]) && $parts[1] !== '') {
                $values['patient_last_name'] = $parts[1];
            }
        }

        if (filled($registration->sex)) {
            $values['patient_gender'] = (string) $registration->sex;
        }

        return $values;
    }
}
