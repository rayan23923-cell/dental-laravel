<?php

namespace App\Services;

use App\Models\PatientRegistration;

/**
 * The infectious-disease/viral-hepatitis lab screening gate — one shared
 * check reused everywhere a patient registration must be confirmed
 * `screening_status === 'clear'` before proceeding (payment, starting a
 * task), instead of a divergent copy in each caller. Mirrors why
 * `TaskStarter` itself was extracted (see that class's docblock).
 */
class PatientScreeningGate
{
    /**
     * @throws PatientScreeningException
     */
    public static function ensureClear(PatientRegistration $registration): void
    {
        if ($registration->screening_status !== 'clear') {
            throw new PatientScreeningException(
                'لا يمكن المتابعة قبل تأكيد سلامة المريض من الأمراض المعدية عبر فحص المختبر.'
            );
        }
    }
}
