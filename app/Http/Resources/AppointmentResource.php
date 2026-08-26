<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AppointmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'full_name' => $this->full_name,
            'patient_id' => $this->patient_id,
            'patient_registration_id' => $this->patient_registration_id,
            'doctor_id' => $this->doctor_id,
            'task_id' => $this->task_id,
            'appointment_date' => $this->appointment_date,
            'confirmed_by_accountant' => $this->confirmed_by_accountant,
            'pinned' => $this->pinned,
            // Null-guarded inside whenLoaded, same reasoning as
            // PaymentResource: an appointment has at most one of the two
            // set, so the *other* relation is loaded-but-empty and
            // whenLoaded() still runs its closure.
            'patient' => $this->whenLoaded('patient', fn () => $this->patient ? ['id' => $this->patient->id, 'name' => $this->patient->name] : null),
            'patient_registration' => $this->whenLoaded('patientRegistration', fn () => $this->patientRegistration ? [
                'id' => $this->patientRegistration->id,
                'name' => $this->patientRegistration->name,
                'phone' => $this->patientRegistration->phone,
            ] : null),
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'full_name' => $this->doctor->full_name]),
            'task' => $this->whenLoaded('task', fn () => ['id' => $this->task->id, 'title' => $this->task->title]),
            'paid_total' => $this->whenLoaded('payments', fn () => $this->payments->sum('amount')),
        ];
    }
}
