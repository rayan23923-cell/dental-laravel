<?php

namespace App\Support;

use App\Models\TaskInstance;
use Illuminate\Http\Request;

/**
 * Case-sheet grades are numbers only (2026-10-15, by request), matching
 * resources/js/numericGrade.js: Arabic digits become Western, an old
 * "9/10" keeps its 9. TaskScoring reads these as numbers, so a "9/10"
 * used to count as 0 points.
 */
class CaseSheetGrades
{
    public const RULES = ['nullable', 'numeric', 'min:0', 'max:1000'];

    /** A step's max when its task sets none (the scoring template's default). */
    public const DEFAULT_MAX = 10;

    /**
     * Each grade column's max (2026-10-15, "لاتقبل اكثر من الدرجة المقررة"):
     * the linked task's step max when its scoring has steps, else 10.
     *
     * @param  array<int, array{key: string}>  $stages
     * @return array<string, float>
     */
    public static function maxes(array $stages, bool $withDiagnosis, ?int $taskInstanceId): array
    {
        $maxes = [];
        if ($withDiagnosis) {
            $maxes['diagnosis_grade'] = (float) self::DEFAULT_MAX;
        }
        foreach ($stages as $stage) {
            $maxes["stage_{$stage['key']}_grade"] = (float) self::DEFAULT_MAX;
        }

        $steps = $taskInstanceId ? (TaskInstance::with('task')->find($taskInstanceId)?->task?->scoring['steps'] ?? []) : [];
        foreach ($steps as $step) {
            $column = $step['key'] === 'diagnosis' ? 'diagnosis_grade' : "stage_{$step['key']}_grade";
            if (isset($maxes[$column]) && is_numeric($step['max'] ?? null)) {
                $maxes[$column] = (float) $step['max'];
            }
        }

        return $maxes;
    }

    /** Validation rules for each grade column, capped at its max. */
    public static function rules(array $maxes): array
    {
        return collect($maxes)->map(fn ($max) => ['nullable', 'numeric', 'min:0', 'max:'.$max])->all();
    }

    /**
     * Rewrites the given grade inputs in place before validation. With
     * `$maxes` (column => max), a number above its max is lowered to it, so
     * a grade saved before the cap existed never blocks a later save.
     */
    public static function normalize(Request $request, array $keys, array $maxes = []): void
    {
        $clean = [];
        foreach ($keys as $key) {
            if ($request->has($key)) {
                $value = self::toNumber($request->input($key));
                if (isset($maxes[$key]) && is_numeric($value) && (float) $value > $maxes[$key]) {
                    $value = (string) (0 + $maxes[$key]);
                }
                $clean[$key] = $value;
            }
        }
        $request->merge($clean);
    }

    public static function toNumber(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        $s = strtr(trim((string) $value), [
            '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
            '۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4', '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
            '٫' => '.', ',' => '.',
        ]);
        if (str_contains($s, '/')) {
            $s = trim(explode('/', $s)[0]);
        }

        return $s === '' ? null : $s;
    }
}
