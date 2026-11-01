<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
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

    /** The stages a student picks from (2026-11-01, by request: five by default). */
    public const STAGES = ['المرحلة الأولى', 'المرحلة الثانية', 'المرحلة الثالثة', 'المرحلة الرابعة', 'المرحلة الخامسة'];

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
        $person = trim((string) ($validated['discount_person_name'] ?? ''));

        return array_merge($validated, [
            'discount_eligible' => $eligible,
            'discount_type' => $type,
            'discount_stage' => $type === 'student' && $stage !== '' ? $stage : null,
            'discount_workplace' => $type === 'employee' && $workplace !== '' ? $workplace : null,
            'discount_person_name' => $type !== null && $person !== '' ? $person : null,
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

    /** "طالب · أحمد علي · المرحلة الرابعة" / "موظف · سارة · الصيدلية" — who the discount is for. */
    public static function whoLabel(PatientRegistration $registration): string
    {
        $employee = $registration->discount_type === 'employee';
        $detail = $employee ? $registration->discount_workplace : $registration->discount_stage;

        return implode(' · ', array_filter([$employee ? 'موظف' : 'طالب', $registration->discount_person_name, $detail]));
    }

    /**
     * What printouts show for a discounted amount (2026-10-25, by request):
     * who the discount is for, then the percentage and the full price it
     * was taken from, e.g. "طالب · المرحلة الرابعة — خصم 50% من 20,000".
     * The percentage is worked out from what was actually paid, so it stays
     * right after the settings change. Null when the patient is not eligible.
     */
    public static function printLine(?PatientRegistration $registration, float $paid, ?float $full, string $currency = ''): ?string
    {
        if (! $registration?->discount_eligible) {
            return null;
        }

        $line = self::whoLabel($registration);
        if ($full !== null && $full > 0 && $paid < $full) {
            $line .= ' — خصم '.self::formatPercent((1 - $paid / $full) * 100).'% من '.trim(number_format($full).' '.$currency);
        }

        return $line;
    }

    /** Short form for report tables: "طالب · المرحلة الرابعة 50%"; null when not eligible. */
    public static function shortLabel(?PatientRegistration $registration, float $paid, ?float $full): ?string
    {
        if (! $registration?->discount_eligible) {
            return null;
        }

        $who = self::whoLabel($registration);

        return $full !== null && $full > 0 && $paid < $full
            ? $who.' '.self::formatPercent((1 - $paid / $full) * 100).'%'
            : $who;
    }

    /**
     * The amount, the discount and the amount after it, each on its own
     * (2026-10-25, by request: "1000, خصم 50%, 500"). `percent` is worked
     * out from what was actually paid and is null when nothing was taken
     * off. Null when the patient is not eligible.
     *
     * @return array{who: string, percent: ?string, full: ?float, paid: float}|null
     */
    public static function breakdown(?PatientRegistration $registration, float $paid, ?float $full): ?array
    {
        if (! $registration?->discount_eligible) {
            return null;
        }

        $discounted = $full !== null && $full > 0 && $paid < $full;

        return [
            'who' => self::whoLabel($registration),
            'percent' => $discounted ? self::formatPercent((1 - $paid / $full) * 100) : null,
            'full' => $discounted ? $full : null,
            'paid' => $paid,
        ];
    }

    /**
     * The undiscounted amount a payment was taken from: the price recorded
     * with it (2026-11-01, by request: the price of the day, not today's).
     */
    public static function fullAmountFor(Payment $payment, ?ClinicSetting $settings = null): ?float
    {
        if ($payment->full_amount !== null) {
            return (float) $payment->full_amount;
        }

        return self::currentFullAmountFor($payment, $settings);
    }

    /**
     * What a registration's recorded payments of one kind ('lab' or
     * 'service') add up to: [paid, full at the time], or null when nothing
     * was paid yet, so tickets and slips show the price of the day.
     *
     * @return array{0: float, 1: ?float}|null
     */
    public static function recorded(PatientRegistration $registration, string $kind): ?array
    {
        $payments = $registration->relationLoaded('payments')
            ? $registration->payments
            : $registration->payments()->get(['id', 'type', 'amount', 'full_amount']);
        $payments = $payments->filter(fn ($p) => $kind === Payment::TYPE_LAB ? $p->type === Payment::TYPE_LAB : $p->type !== Payment::TYPE_LAB);

        if ($payments->isEmpty()) {
            return null;
        }

        $full = $payments->every(fn ($p) => $p->full_amount !== null) ? (float) $payments->sum('full_amount') : null;

        return [(float) $payments->sum('amount'), $full];
    }

    /** Today's undiscounted price for a payment (what a new one is taken from). */
    public static function currentFullAmountFor(Payment $payment, ?ClinicSetting $settings = null): ?float
    {
        if ($payment->appointment_id && ! $payment->patient_registration_id) {
            return null;
        }

        if ($payment->type === Payment::TYPE_LAB) {
            $fee = ($settings ?? ClinicSetting::current())->lab_fee;

            return $fee === null ? null : (float) $fee;
        }

        $registration = $payment->patientRegistration;
        // Without loading the relation, so lists that leave the service out
        // (the payments list) keep their shape; only eligible rows ask.
        $price = $registration?->relationLoaded('service')
            ? $registration->service?->price
            : ($registration?->service_id ? Service::whereKey($registration->service_id)->value('price') : null);

        return $price === null ? null : (float) $price;
    }

    private static function formatPercent(float $percent): string
    {
        return rtrim(rtrim(number_format($percent, 1, '.', ''), '0'), '.');
    }
}
