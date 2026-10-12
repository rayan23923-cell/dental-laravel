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
        $fee = ClinicSetting::current()->lab_fee;

        if ($fee === null || (float) $fee <= 0 || self::previousScreening($registration)) {
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
     * @param  Collection<int, PatientRegistration>  $registrations
     * @return Collection<int, PatientRegistration>
     */
    public static function previousScreenings(Collection $registrations): Collection
    {
        $days = self::validityDays();
        $phones = $registrations->pluck('phone')->map(fn ($p) => trim((string) $p))->filter()->unique();

        if ($days <= 0 || $phones->isEmpty()) {
            return collect();
        }

        $earlier = PatientRegistration::whereIn('phone', $phones->all())
            ->where('screening_status', 'clear')
            // Only real screenings count, so reusing never extends the window.
            ->whereNull('screening_reused_from')
            ->where('screening_checked_at', '>=', now()->subDays($days))
            ->orderByDesc('screening_checked_at')
            ->get(['id', 'name', 'phone', 'screening_checked_at']);

        $result = collect();
        foreach ($registrations as $registration) {
            $match = $earlier->first(fn ($e) => $e->phone === trim((string) $registration->phone) && $e->id !== $registration->id);
            if ($match) {
                $result->put($registration->id, $match);
            }
        }

        return $result;
    }
}
