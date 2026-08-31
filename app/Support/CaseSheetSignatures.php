<?php

namespace App\Support;

use App\Models\TaskInstance;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Auto-captured signatures for the case sheets' "*_signature" fields
 * (2026-08-30, by request — replacing a free-typed name with the actual
 * authenticated signer's name + timestamp, captured server-side so it
 * can't be typed as anyone else). A field only ever gets a value through
 * the client sending {@see SENTINEL}, stamped here with the real signer;
 * once set it's immutable — `applyPending()` always re-asserts the stored
 * value over anything the client sends afterward, whether a resubmit of
 * the same form or deliberate tampering.
 *
 * The field list below is deliberately just the fields that ARE a
 * signature — the companion name/date/grade/notes fields next to each one
 * (`senior_doctor_name`, `approval_date`, `diagnosis_grade`,
 * `stage_*_date`, `stage_*_grade`, `supervisor_notes`…) stay ordinary
 * editable fields, unchanged by this class. `prevention-records` has no
 * separate `senior_signature` column — its "Signature" section's own
 * `senior_name` (a subkey of the `patient_data` JSON blob, see
 * `App\Support\PreventionForm`) plays that role, so it's the one
 * converted there instead of a same-named flat column.
 *
 * Completion is a separate, explicit action (`TaskInstanceGrader::complete()`,
 * triggered from the Task Progress screen) — this class only answers
 * "are all of this record's signatures in place yet" via `allSignedForInstance()`,
 * which that screen uses to surface a "ready to mark complete" hint next
 * to the existing complete button, per the user's own framing: signing
 * off doesn't auto-complete anything, it just makes the option visible.
 */
class CaseSheetSignatures
{
    public const SENTINEL = '__SIGN__';

    private const PROSTHODONTICS_STAGES = [
        'preliminary', 'surveying', 'final', 'jawrel', 'trial', 'flasking', 'rpd', 'adjust1', 'finaleval',
    ];

    private const COMPLETE_DENTURE_STAGES = [
        'preliminary', 'surveying', 'final', 'jawrel', 'trial', 'flasking', 'cd', 'adjust1', 'finaleval',
    ];

    /** @return array<int, array{key: string, group?: string}> */
    public static function fieldsFor(string $resource): array
    {
        return match ($resource) {
            'dental-charts', 'surgeries', 'periodontal-charts', 'advanced-periodontal-charts' => [['key' => 'senior_signature']],
            'orthodontics-records' => [['key' => 'supervisor_signature']],
            'prevention-records' => [
                ['key' => 'senior_name', 'group' => 'patient_data'],
                ['key' => 'supervisor_signature'],
            ],
            'oral-medicine-charts' => [
                ['key' => 'staff_signature', 'group' => 'student_visits'],
                ['key' => 'supervisor_signature'],
            ],
            'prosthodontics-records' => self::stageSpecs(self::PROSTHODONTICS_STAGES),
            'complete-denture-records' => self::stageSpecs(self::COMPLETE_DENTURE_STAGES),
            default => [],
        };
    }

    /** @return array<int, array{key: string}> */
    private static function stageSpecs(array $stages): array
    {
        $specs = [['key' => 'diagnosis_instructor_signature']];
        foreach ($stages as $stage) {
            // "يجب ان يملئ حقل الدرجة والتاريخ حتى يوقع" (2026-08-30) — a
            // stage can't be signed off until its own Grade and Date are
            // filled in, so a signature never attests to a still-blank
            // evaluation. Checked server-side (not just the client-side
            // disabled button) so a direct API call can't skip it either.
            $specs[] = [
                'key' => "stage_{$stage}_signature",
                'requires' => ["stage_{$stage}_date", "stage_{$stage}_grade"],
            ];
        }

        return $specs;
    }

    /**
     * Rewrites every signature field this resource defines that's present
     * in $data: a field the record already has a value for is forced back
     * to that stored value (immutable); a field the client sent
     * {@see SENTINEL} for gets stamped with $signerName + now() — but only
     * once every field the spec's `requires` names (if any) already has a
     * value, in $data or on $existing; anything else sent for a signature
     * key is dropped, since these are no longer free-typed fields a client
     * can just write text into.
     */
    public static function applyPending(string $resource, array $data, ?Model $existing, string $signerName): array
    {
        foreach (self::fieldsFor($resource) as $spec) {
            $data = isset($spec['group'])
                ? self::applyGrouped($data, $existing, $spec['group'], $spec['key'], $signerName)
                : self::applyFlat($data, $existing, $spec['key'], $signerName, $spec['requires'] ?? []);
        }

        return $data;
    }

    private static function applyFlat(array $data, ?Model $existing, string $key, string $signerName, array $requires = []): array
    {
        if (! array_key_exists($key, $data)) {
            return $data;
        }

        $existingValue = $existing?->getAttribute($key);

        if (filled($existingValue)) {
            $data[$key] = $existingValue;
        } elseif ($data[$key] === self::SENTINEL && self::requirementsMet($requires, $data, $existing)) {
            $data[$key] = self::stamp($signerName);
        } else {
            unset($data[$key]);
        }

        return $data;
    }

    private static function requirementsMet(array $requires, array $data, ?Model $existing): bool
    {
        foreach ($requires as $requiredKey) {
            if (blank($data[$requiredKey] ?? $existing?->getAttribute($requiredKey))) {
                return false;
            }
        }

        return true;
    }

    /** The client always posts a grouped column's whole JSON blob as one string — see `EnforceCaseSheetAccess::changedFields()`'s doc comment for the same fact. */
    private static function applyGrouped(array $data, ?Model $existing, string $group, string $key, string $signerName): array
    {
        if (! array_key_exists($group, $data)) {
            return $data;
        }

        $decoded = json_decode((string) $data[$group], true);
        if (! is_array($decoded)) {
            return $data;
        }

        $existingRaw = $existing?->getAttribute($group);
        $existingDecoded = is_string($existingRaw) ? json_decode($existingRaw, true) : null;
        $existingValue = is_array($existingDecoded) ? ($existingDecoded[$key] ?? null) : null;

        if (filled($existingValue)) {
            $decoded[$key] = $existingValue;
        } elseif (($decoded[$key] ?? null) === self::SENTINEL) {
            $decoded[$key] = self::stamp($signerName);
        } else {
            unset($decoded[$key]);
        }

        $data[$group] = json_encode($decoded);

        return $data;
    }

    private static function stamp(string $signerName): string
    {
        return $signerName.' — '.now()->format('Y-m-d H:i');
    }

    /** `User` (staff) uses `full_name`; `Doctor` uses `name` — try both rather than assuming the guard. */
    public static function signerName(Request $request): string
    {
        $user = $request->user();

        return $user?->full_name ?? $user?->name ?? 'Unknown';
    }

    /** True once every signature field this resource defines is filled in on $record. */
    public static function allSigned(string $resource, Model $record): bool
    {
        $specs = self::fieldsFor($resource);
        if ($specs === []) {
            return false;
        }

        foreach ($specs as $spec) {
            $value = isset($spec['group'])
                ? self::groupedValue($record, $spec['group'], $spec['key'])
                : $record->getAttribute($spec['key']);

            if (blank($value)) {
                return false;
            }
        }

        return true;
    }

    private static function groupedValue(Model $record, string $group, string $key): mixed
    {
        $raw = $record->getAttribute($group);
        $decoded = is_string($raw) ? json_decode($raw, true) : null;

        return is_array($decoded) ? ($decoded[$key] ?? null) : null;
    }

    /**
     * Used by `TaskProgressGroupSummary` to surface a "ready to mark
     * complete" hint on the Task Progress screen once every signature on
     * the linked case-sheet record is in place — never completes anything
     * itself, that stays the existing explicit `TaskInstanceGrader::complete()`
     * action.
     */
    public static function allSignedForInstance(string $resource, TaskInstance $taskInstance): bool
    {
        $modelClass = CaseSheetResolver::modelFor($resource);
        if (! $modelClass) {
            return false;
        }

        $record = $modelClass::where('task_instances_id', $taskInstance->id)->first();

        return $record !== null && self::allSigned($resource, $record);
    }
}
