<?php

namespace App\Support;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * Saves one stage date or grade the moment it changes (2026-10-15,
 * "يكون الإدخال يخزن بعد التغيير مباشرة"), so the stages table needs no
 * Save button. The request carries exactly one column; who may change it
 * is still decided by the `case-sheet` middleware, as for a full save.
 */
class CaseSheetStageField
{
    /** @return array{field: string, value: mixed} */
    public static function save(Request $request, Model $record, array $stages, bool $withDiagnosis): array
    {
        $maxes = CaseSheetGrades::maxes($stages, $withDiagnosis, $record->task_instances_id);
        $rules = CaseSheetGrades::rules($maxes);
        foreach ($stages as $stage) {
            $rules["stage_{$stage['key']}_date"] = ['nullable', 'date'];
        }
        if ($withDiagnosis) {
            $rules['diagnosis_date'] = ['nullable', 'date'];
        }

        $fields = array_values(array_intersect(array_keys($rules), array_keys($request->all())));
        if (count($fields) !== 1) {
            throw ValidationException::withMessages(['field' => 'Send exactly one stage date or grade.']);
        }
        $field = $fields[0];

        CaseSheetGrades::normalize($request, array_keys($maxes), $maxes);
        $value = $request->validate([$field => $rules[$field]])[$field] ?? null;
        $record->update([$field => $value]);

        return ['field' => $field, 'value' => $value];
    }
}
