<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use Illuminate\Support\Collection;

/**
 * The lab result needs the lab fee paid first (2026-10-11). When no fee is
 * configured in clinic settings there is nothing to pay, so the lab is not
 * blocked.
 *
 * A clear result stays valid for `lab_validity_days` (2026-10-12): the same
 * patient (same phone) registering again inside that window is not screened
 * or charged again; the lab reuses the earlier result instead.
 */
class LabFeeGate
{
    /** The refusal message, or null when the result may be recorded. */
    public static function unpaidMessage(PatientRegistration $registration): ?string
    {
        $fee = ClinicSetting::current()->lab_fee;

        if ($fee === null || (float) $fee <= 0) {
            return null;
        }

        if (self::previousScreening($registration)) {
            return null;
        }

        $paid = Payment::where('patient_registration_id', $registration->id)
            ->where('type', Payment::TYPE_LAB)
            ->exists();

        return $paid ? null : 'يجب دفع أجور المختبر قبل تسجيل نتيجة الفحص.';
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
