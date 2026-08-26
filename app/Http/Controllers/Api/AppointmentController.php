<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\AppointmentResource;
use App\Models\Appointment;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AppointmentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $appointments = Appointment::with(['patient', 'patientRegistration', 'doctor', 'task', 'payments'])
            ->when($request->integer('doctor_id'), fn ($q, $id) => $q->where('doctor_id', $id))
            ->when($request->integer('patient_id'), fn ($q, $id) => $q->where('patient_id', $id))
            ->when(
                $request->integer('patient_registration_id'),
                fn ($q, $id) => $q->where('patient_registration_id', $id)
            )
            ->when($request->has('pinned'), fn ($q) => $q->where('pinned', $request->boolean('pinned')))
            ->orderByDesc('appointment_date')
            ->paginate(15);

        return AppointmentResource::collection($appointments)->response();
    }

    public function show(Appointment $appointment): JsonResponse
    {
        $appointment->load(['patient', 'patientRegistration', 'doctor', 'task', 'payments']);

        return (new AppointmentResource($appointment))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $appointment = Appointment::create($this->validateAppointment($request));

        return (new AppointmentResource($appointment))->response()->setStatusCode(201);
    }

    public function update(Request $request, Appointment $appointment): JsonResponse
    {
        $appointment->update($this->validateAppointment($request, true));

        return (new AppointmentResource($appointment))->response();
    }

    public function destroy(Appointment $appointment): JsonResponse
    {
        $appointment->delete();

        return response()->json(null, 204);
    }

    /**
     * `patient_registration_id` replaces `patient_id` as the form-facing
     * link going forward (see the migration that added it) — required on
     * create, optional on update so editing an appointment created before
     * this column existed doesn't force picking one retroactively.
     * `patient_id` itself is intentionally no longer accepted here; it
     * stays whatever it already was for legacy rows.
     */
    private function validateAppointment(Request $request, bool $partial = false): array
    {
        if ($request->input('patient_registration_id') === '') {
            $request->merge(['patient_registration_id' => null]);
        }

        return $request->validate([
            'full_name' => [$partial ? 'sometimes' : 'required', 'string', 'max:250'],
            'patient_registration_id' => [$partial ? 'sometimes' : 'required', 'nullable', 'exists:patients_simple,id'],
            'doctor_id' => [$partial ? 'sometimes' : 'required', 'exists:users,id'],
            'task_id' => [$partial ? 'sometimes' : 'required', 'exists:tasks,id'],
            'appointment_date' => [$partial ? 'sometimes' : 'required', 'date'],
            'confirmed_by_accountant' => ['boolean'],
            'pinned' => ['boolean'],
        ]);
    }
}
