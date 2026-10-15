<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use Illuminate\Contracts\View\View;

/**
 * Printable registration ticket — a standalone Blade doc (own letterhead,
 * `window.print()`, no app chrome), same pattern as `DoctorPrintController`.
 * Kept separate from `PatientRegistrationController` (the Inertia
 * controller) for the same reason `DoctorPrintController` is separate from
 * `DoctorController`: this isn't an Inertia page.
 *
 * Lets a desk clerk reprint an already-registered patient's ticket from
 * the web — until now the ticket only ever printed once, and only on the
 * Android POS device, right at creation time.
 */
class PatientRegistrationPrintController extends Controller
{
    public function ticket(PatientRegistration $patientRegistration): View
    {
        $patientRegistration->load(['service', 'registerDay'])
            ->loadSum(['payments as service_paid' => fn ($q) => $q->where('type', Payment::TYPE_SERVICE)], 'amount');

        return view('print.patient-registration-ticket', [
            'settings' => ClinicSetting::current(),
            'registration' => $patientRegistration,
        ]);
    }
}
