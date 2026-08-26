<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'appointment_id' => $this->appointment_id,
            'patient_registration_id' => $this->patient_registration_id,
            'amount' => $this->amount,
            'paid_by' => $this->paid_by,
            'paid_at' => $this->paid_at,
            // Null-guarded inside whenLoaded: exactly one of these two is
            // set on any payment, so the *other* relation is loaded-but-
            // empty and whenLoaded() still runs its closure.
            'appointment' => $this->whenLoaded('appointment', fn () => $this->appointment ? [
                'id' => $this->appointment->id,
                'full_name' => $this->appointment->full_name,
            ] : null),
            'patient_registration' => $this->whenLoaded('patientRegistration', fn () => $this->patientRegistration ? [
                'id' => $this->patientRegistration->id,
                'name' => $this->patientRegistration->name,
                'phone' => $this->patientRegistration->phone,
            ] : null),
        ];
    }
}
