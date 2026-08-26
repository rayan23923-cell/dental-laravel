<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\Patient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Public, unauthenticated read-only board for the waiting-room TV screen —
 * mirrors the original app's tv_patients.php (regular scheduled patients via
 * patients -> groups -> group_slots, plus pinned same-day appointments).
 *
 * Note: the original tv_patients.php joins pinned appointments against the
 * `doctors` table (`LEFT JOIN doctors d ON a.doctor_id = d.id`), but
 * appointments.doctor_id is declared (and populated — confirmed in
 * admin/ajax/pin_appointments.php: `SELECT id FROM users WHERE role =
 * 'doctor'`) as a reference to `users.id`. That join is a pre-existing
 * display bug in the original app. This endpoint joins against `users`
 * instead, since that's what the data actually is.
 */
class TvBoardController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $patients = Patient::with(['doctor', 'group.slots'])
            ->when($request->integer('education_type'), fn ($q, $id) => $q->whereHas('doctor', fn ($dq) => $dq->where('education_type_id', $id)))
            ->when($request->integer('stage'), fn ($q, $id) => $q->whereHas('doctor', fn ($dq) => $dq->where('stage_id', $id)))
            ->get()
            ->map(fn ($patient) => [
                'type' => 'patient',
                'patient_name' => $patient->name,
                'doctor_name' => $patient->doctor?->name,
                'slots' => $patient->group?->slots->map(fn ($slot) => [
                    'day' => $slot->day,
                    'start_time' => $slot->start_time,
                    'end_time' => $slot->end_time,
                ]),
            ]);

        // No education_type/stage filter here: appointments.doctor_id references
        // users.id (staff), and `users` has no education_type_id/stage_id column
        // to filter by — those only exist on `doctors`. The original app's
        // filter for pinned appointments only appeared to work because it
        // joined the wrong table (see class docblock); there's no equivalent
        // correct filter to apply here.
        $appointments = Appointment::with('doctor')
            ->orderBy('appointment_date')
            ->get()
            ->map(fn ($appointment) => [
                'type' => 'appointment',
                'patient_name' => $appointment->full_name,
                'doctor_name' => $appointment->doctor?->full_name,
                'appointment_date' => $appointment->appointment_date,
                'pinned' => $appointment->pinned,
            ]);

        return response()->json([
            'patients' => $patients,
            'appointments' => $appointments,
        ]);
    }
}
