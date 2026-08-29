<?php

namespace App\Support;

/**
 * Which fields on each of the 8 case-sheet resources a *supervisor* (any
 * staff principal, per `App\Services\CaseSheetAccess::isViewOnly()`) may
 * edit, and a *doctor* may not — the inverse of every other field, which
 * only the owning doctor may edit and staff cannot (see
 * `App\Http\Middleware\EnforceCaseSheetAccess`).
 *
 * Confirmed via a fresh read of all 8 models (2026-08-28) that this isn't
 * a uniform field pair across every resource: `dental-charts`,
 * `surgeries`, `periodontal-charts` already have a `notes` +
 * `senior_signature`-style pair from the original app's own schema.
 * `prosthodontics-records`/`complete-denture-records` have a
 * structurally different but equally supervisor-facing mechanism instead
 * — a `diagnosis_instructor_signature` field plus a
 * `stage_{name}_{signature,date,grade}` triple per named stage — reused
 * as-is rather than bolting on a redundant generic pair. The remaining 3
 * (`orthodontics-records`, `prevention-records`, `oral-medicine-charts`)
 * had neither, so `supervisor_notes`/`supervisor_signature` were added
 * to just those three (see the matching migration).
 *
 * **Correction (2026-08-29)**: the "had neither" premise above was wrong
 * for `prevention-records` specifically — it already ports the original
 * app's own `senior_name`/`signature_date` pair (see
 * `App\Support\PreventionForm`'s "Signature" section), just missed by the
 * 2026-08-28 read because both live as subkeys of the `patient_data` JSON
 * blob (a `group`-mechanism field, see `SectionedForm.vue`) rather than
 * real top-level columns like every other resource's supervisor fields.
 * Registered here now that `EnforceCaseSheetAccess::changedFields()` can
 * actually diff a grouped subkey correctly (same date). The newer
 * `supervisor_notes`/`supervisor_signature` pair stays too — it's a
 * genuine second field (staff's own notes), not a duplicate of the
 * doctor-facing senior sign-off.
 */
class CaseSheetSupervisorFields
{
    private const PROSTHODONTICS_STAGES = [
        'preliminary', 'surveying', 'final', 'jawrel', 'trial', 'flasking', 'rpd', 'adjust1', 'finaleval',
    ];

    private const COMPLETE_DENTURE_STAGES = [
        'preliminary', 'surveying', 'final', 'jawrel', 'trial', 'flasking', 'cd', 'adjust1', 'finaleval',
    ];

    public static function fieldsFor(string $resource): array
    {
        return match ($resource) {
            'dental-charts' => ['notes', 'senior_doctor_name', 'senior_signature'],
            'surgeries' => ['notes', 'senior_doctor_name', 'approval_date', 'senior_signature'],
            'periodontal-charts' => ['notes', 'clinical_notes', 'senior_doctor_name', 'approval_date', 'senior_signature'],
            'prosthodontics-records' => self::stageFields(self::PROSTHODONTICS_STAGES),
            'complete-denture-records' => self::stageFields(self::COMPLETE_DENTURE_STAGES),
            'orthodontics-records', 'oral-medicine-charts' => ['supervisor_notes', 'supervisor_signature'],
            'prevention-records' => ['senior_name', 'signature_date', 'supervisor_notes', 'supervisor_signature'],
            default => [],
        };
    }

    private static function stageFields(array $stages): array
    {
        $fields = ['diagnosis_instructor_signature'];
        foreach ($stages as $stage) {
            $fields[] = "stage_{$stage}_signature";
            $fields[] = "stage_{$stage}_date";
            $fields[] = "stage_{$stage}_grade";
        }

        return $fields;
    }
}
