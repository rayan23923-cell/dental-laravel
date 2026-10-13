<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\PatientRegistration;
use App\Models\TaskInstance;

/**
 * Keeps an appointment's patient/doctor display in step with the
 * registered patient it's linked to (`patient_registration_id`), per the
 * 2026-09-09 request: an appointment's `full_name` should never drift
 * from the registration it points at, and once that patient is linked to
 * a doctor for a case sheet (`TaskStarter::start()`), the appointment
 * should show that treating doctor too — not just whichever staff user
 * booked the appointment (`Appointment::doctor()`, unrelated to this).
 *
 * Two call sites: `TaskStarter::start()` (the actual "patient linked to a
 * case sheet" moment) fans out to every appointment already booked for
 * that patient/task, and the Appointment controllers call `refresh()`
 * after every create/update so a newly booked or edited appointment picks
 * up an existing assignment immediately instead of waiting for the next
 * `TaskStarter` run.
 */
class AppointmentPatientSync
{
    public static function syncForPatient(PatientRegistration $patientRegistration, int $taskId): void
    {
        Appointment::where('patient_registration_id', $patientRegistration->id)
            ->where('task_id', $taskId)
            ->get()
            ->each(fn (Appointment $appointment) => self::refresh($appointment, $patientRegistration));
    }

    public static function refresh(Appointment $appointment, ?PatientRegistration $patientRegistration = null): void
    {
        $patientRegistration ??= $appointment->patientRegistration;

        if (! $patientRegistration) {
            return;
        }

        $treatingDoctorId = TaskInstance::where('patient_registration_id', $patientRegistration->id)
            ->where('task_id', $appointment->task_id)
            ->whereIn('status', ['assigned', 'completed'])
            ->latest('assigned_date')
            ->value('doctor_id');

        $appointment->update([
            'full_name' => $patientRegistration->name,
            'case_sheet_doctor_id' => $treatingDoctorId,
        ]);
    }
}
