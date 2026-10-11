<?php

namespace App\Support;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;

/**
 * The lab result needs the lab fee paid first (2026-10-11). When no fee is
 * configured in clinic settings there is nothing to pay, so the lab is not
 * blocked.
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

        $paid = Payment::where('patient_registration_id', $registration->id)
            ->where('type', Payment::TYPE_LAB)
            ->exists();

        return $paid ? null : 'يجب دفع أجور المختبر قبل تسجيل نتيجة الفحص.';
    }
}
