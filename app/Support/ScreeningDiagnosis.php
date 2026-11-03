<?php

namespace App\Support;

use App\Models\PatientRegistration;

/**
 * What a "غير سليم" lab result is (2026-11-03, by request): the lab picks
 * one or more of B (التهاب الكبد B), C (التهاب الكبد C) and HIV. Kept on
 * `patients_simple.screening_diagnoses` and printed on the lab slip, the
 * lab fee receipt and the patient's records.
 */
class ScreeningDiagnosis
{
    /** Code => printed label, in this order everywhere. */
    public const LABELS = [
        'B' => 'التهاب الكبد B',
        'C' => 'التهاب الكبد C',
        'HIV' => 'HIV',
    ];

    public const CODES = ['B', 'C', 'HIV'];

    /** Only known codes, de-duplicated, in the fixed order. */
    public static function normalize(?array $codes): array
    {
        $codes = array_map(fn ($c) => strtoupper(trim((string) $c)), $codes ?? []);

        return array_values(array_filter(self::CODES, fn ($c) => in_array($c, $codes, true)));
    }

    /** "التهاب الكبد B، HIV" — null when nothing is recorded or the result is not flagged. */
    public static function text(PatientRegistration $registration): ?string
    {
        if ($registration->screening_status !== 'flagged') {
            return null;
        }

        $codes = self::normalize($registration->screening_diagnoses);

        return $codes ? implode('، ', array_map(fn ($c) => self::LABELS[$c], $codes)) : null;
    }
}
