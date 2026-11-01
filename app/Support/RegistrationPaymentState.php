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
        // This patient's fee: less the student discount when eligible (2026-10-25).
        $settings = ClinicSetting::current();
        $labFee = StudentDiscount::labFee($registration, $settings);
        // A still-valid earlier clear result (same phone) the lab can reuse
        // instead of screening and charging again (2026-10-12).
        $previous = $registration->screening_status === 'pending' ? LabFeeGate::previousScreening($registration) : null;
        // The lab fee's full price as recorded with the payment (2026-11-01), else today's.
        $labFull = $lab->isNotEmpty() && $lab->every(fn ($p) => $p->full_amount !== null)
            ? (float) $lab->sum('full_amount')
            : ($settings->lab_fee !== null ? (float) $settings->lab_fee : null);

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
            'lab_fee' => $labFee,
            'lab_paid' => $lab->isNotEmpty(),
            'lab_paid_amount' => (float) $lab->sum('amount'),
            // The lab slip's discount line (2026-10-25): from what was paid,
            // or this patient's fee while still unpaid.
            'lab_discount_line' => StudentDiscount::printLine(
                $registration,
                $lab->isNotEmpty() ? (float) $lab->sum('amount') : (float) ($labFee ?? 0),
                $labFull,
                (string) $settings->clinic_currency,
            ),
            // The same as separate amounts for the slip's rows (2026-10-25).
            'lab_discount' => StudentDiscount::breakdown(
                $registration,
                $lab->isNotEmpty() ? (float) $lab->sum('amount') : (float) ($labFee ?? 0),
                $labFull,
            ),
            // Free with a care code (2026-11-01): no service or lab fee.
            'supported' => $registration->support_code_id !== null,
            'lab_validity_days' => LabFeeGate::validityDays(),
            'previous_screening' => $previous ? [
                'id' => $previous->id,
                'checked_at' => $previous->screening_checked_at,
                'name' => $previous->name,
                'phone' => $previous->phone,
                'matched_by' => $previous->matched_by,
            ] : null,
        ];
    }
}
