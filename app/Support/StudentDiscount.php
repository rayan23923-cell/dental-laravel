<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Service;

/**
 * Student discount (2026-10-25, by request): a registration marked
 * `discount_eligible` pays the service price and the lab fee less each
 * one's own percentage — `register_services.student_discount_percent` and
 * `clinic_settings.lab_student_discount_percent`, both 50 by default.
 */
class StudentDiscount
{
    public const DEFAULT_PERCENT = 50.0;

    /** Who can be eligible (2026-10-25): students and employees, same percentages. */
    public const TYPES = ['student', 'employee'];

    /**
     * The registration's discount fields made consistent: not eligible
     * clears them all; eligible defaults to a student, and keeps only the
     * stage (student) or the workplace (employee), blank as null.
     */
    public static function normalize(array $validated): array
    {
        $eligible = (bool) ($validated['discount_eligible'] ?? false);
        $type = $eligible ? (($validated['discount_type'] ?? null) ?: 'student') : null;
        $stage = trim((string) ($validated['discount_stage'] ?? ''));
        $workplace = trim((string) ($validated['discount_workplace'] ?? ''));

        return array_merge($validated, [
            'discount_eligible' => $eligible,
            'discount_type' => $type,
            'discount_stage' => $type === 'student' && $stage !== '' ? $stage : null,
            'discount_workplace' => $type === 'employee' && $workplace !== '' ? $workplace : null,
        ]);
    }

    /** `$amount` less `$percent` (clamped to 0–100), rounded to 2 places. */
    public static function apply(float $amount, ?float $percent): float
    {
        $percent = max(0.0, min(100.0, $percent ?? self::DEFAULT_PERCENT));

        return round($amount * (100 - $percent) / 100, 2);
    }

    /** What this patient pays for the service. */
    public static function servicePrice(Service $service, bool $eligible): ?float
    {
        if ($service->price === null) {
            return null;
        }

        return $eligible
            ? self::apply((float) $service->price, self::percent($service->student_discount_percent))
            : (float) $service->price;
    }

    /**
     * What this patient pays for the lab test; null when no fee is set.
     * Lists pass `$settings` so it is read once, not per row.
     */
    public static function labFee(?PatientRegistration $registration, ?ClinicSetting $settings = null): ?float
    {
        $settings ??= ClinicSetting::current();
        if ($settings->lab_fee === null) {
            return null;
        }

        return $registration?->discount_eligible
            ? self::apply((float) $settings->lab_fee, self::percent($settings->lab_student_discount_percent))
            : (float) $settings->lab_fee;
    }

    private static function percent($value): float
    {
        return $value === null ? self::DEFAULT_PERCENT : (float) $value;
    }
}
