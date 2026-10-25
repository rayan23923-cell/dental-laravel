<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use Illuminate\Support\Collection;

/**
 * The lab fee is paid when the result is recorded (2026-10-12, by request):
 * the lab picks "سليم" or "غير سليم" and prints one slip that is already
 * paid, instead of a separate payment receipt first. `chargeIfDue()` books
 * the fee as the result is saved. When no fee is configured there is
 * nothing to pay.
 *
 * A clear result stays valid for `lab_validity_days` (2026-10-12): the same
 * patient (same phone) registering again inside that window is not screened
 * or charged again; the lab reuses the earlier result instead.
 */
class LabFeeGate
{
    /**
     * Records the lab fee for this registration unless there is no fee,
     * it is already paid, or an earlier valid result is being reused.
     */
    public static function chargeIfDue(PatientRegistration $registration, ?string $paidBy = null): ?Payment
    {
        // Less the student discount when the patient is eligible (2026-10-25).
        $fee = StudentDiscount::labFee($registration);

        if ($fee === null || $fee <= 0 || self::previousScreening($registration)) {
            return null;
        }

        $paid = Payment::where('patient_registration_id', $registration->id)
            ->where('type', Payment::TYPE_LAB)
            ->lockForUpdate()
            ->exists();

        if ($paid) {
            return null;
        }

        return Payment::create([
            'patient_registration_id' => $registration->id,
            'amount' => $fee,
            'paid_by' => $paidBy,
            'paid_at' => now(),
            'type' => Payment::TYPE_LAB,
        ]);
    }

    /** Days a clear result stays valid; 0 turns reuse off. */
    public static function validityDays(): int
    {
        return (int) (ClinicSetting::current()->lab_validity_days ?? 0);
    }

    /** The latest still-valid clear result of the same patient, if any. */
    public static function previousScreening(PatientRegistration $registration): ?PatientRegistration
    {
        return self::previousScreenings(collect([$registration]))->get($registration->id);
    }

    /**
     * Batched form for a page of registrations: registration id => the
     * earlier registration whose result it can reuse.
     *
     * Matches on the phone or the full name (2026-10-12, by request), so a
     * patient who comes back with another number, or whose number was
     * typed differently, is still found. Each match carries `matched_by`
     * ('phone' or 'name'); a phone match wins over a name match, since
     * two different patients can share a name.
     *
     * @param  Collection<int, PatientRegistration>  $registrations
     * @return Collection<int, PatientRegistration>
     */
    public static function previousScreenings(Collection $registrations): Collection
    {
        $days = self::validityDays();

        if ($days <= 0 || $registrations->isEmpty()) {
            return collect();
        }

        // Only real screenings in the window: small enough to compare in
        // PHP, where names can be normalised (أ/ا, ة/ه, ى/ي, spacing).
        $earlier = PatientRegistration::where('screening_status', 'clear')
            // Only real screenings count, so reusing never extends the window.
            ->whereNull('screening_reused_from')
            ->where('screening_checked_at', '>=', now()->subDays($days))
            ->orderByDesc('screening_checked_at')
            ->get(['id', 'name', 'phone', 'screening_checked_at']);

        $result = collect();
        foreach ($registrations as $registration) {
            $others = $earlier->where('id', '!=', $registration->id);
            $phone = self::normalizePhone($registration->phone);
            $name = self::normalizeName($registration->name);

            $match = $phone !== '' ? $others->first(fn ($e) => self::normalizePhone($e->phone) === $phone) : null;
            $by = 'phone';
            if (! $match && $name !== '') {
                $match = $others->first(fn ($e) => self::normalizeName($e->name) === $name);
                $by = 'name';
            }

            if ($match) {
                $result->put($registration->id, (clone $match)->setAttribute('matched_by', $by));
            }
        }

        return $result;
    }

    /** Digits only, with a leading 964 / 0 dropped, so 0770…, +964770… match. */
    public static function normalizePhone(?string $phone): string
    {
        $digits = preg_replace('/\D+/', '', strtr((string) $phone, ['٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9']));

        return preg_replace('/^(00964|964|0)/', '', $digits);
    }

    /** Arabic spelling variants folded and spacing collapsed. */
    public static function normalizeName(?string $name): string
    {
        $name = strtr(trim((string) $name), ['أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ة' => 'ه', 'ى' => 'ي', 'ـ' => '']);
        $name = preg_replace('/[\x{064B}-\x{0652}]/u', '', $name);

        return mb_strtolower(preg_replace('/\s+/u', ' ', $name));
    }
}
