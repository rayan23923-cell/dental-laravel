<?php

namespace App\Support;

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

    /** Rewrites the given grade inputs in place before validation. */
    public static function normalize(Request $request, array $keys): void
    {
        $clean = [];
        foreach ($keys as $key) {
            if ($request->has($key)) {
                $clean[$key] = self::toNumber($request->input($key));
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
