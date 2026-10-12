<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\Payment;
use App\Models\PatientRegistration;

/**
 * The payment-desk/lab view of one registration, shared by the web and
 * API controllers. Service payments (`is_paid`/`total_paid`) and the lab
 * screening fee (`lab_fee`/`lab_paid`) are kept apart (2026-10-11): paying
 * the lab fee must not make a patient look paid for treatment.
 */
class RegistrationPaymentState
{
    public static function build(PatientRegistration $registration, array $registrationData): array
    {
        $payments = $registration->payments()->orderByDesc('paid_at')->get();
        $service = $payments->where('type', '!=', Payment::TYPE_LAB);
        $lab = $payments->where('type', Payment::TYPE_LAB);
        $labFee = ClinicSetting::current()->lab_fee;
        // A still-valid earlier clear result (same phone) the lab can reuse
        // instead of screening and charging again (2026-10-12).
        $previous = $registration->screening_status === 'pending' ? LabFeeGate::previousScreening($registration) : null;

        return [
            'registration' => $registrationData,
            'payments' => $payments->map(fn ($p) => [
                'id' => $p->id,
                'type' => $p->type,
                'amount' => $p->amount,
                'paid_by' => $p->paid_by,
                'paid_at' => $p->paid_at,
            ])->values(),
            'total_paid' => (float) $service->sum('amount'),
            'is_paid' => $service->isNotEmpty(),
            'lab_fee' => $labFee !== null ? (float) $labFee : null,
            'lab_paid' => $lab->isNotEmpty(),
            'lab_paid_amount' => (float) $lab->sum('amount'),
            'lab_validity_days' => LabFeeGate::validityDays(),
            'previous_screening' => $previous ? [
                'id' => $previous->id,
                'checked_at' => $previous->screening_checked_at,
            ] : null,
        ];
    }
}
