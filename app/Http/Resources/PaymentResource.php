<?php

namespace App\Http\Resources;

use App\Models\ClinicSetting;
use App\Support\StudentDiscount;
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
            'type' => $this->type ?? 'service',
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
                // Archived (soft-deleted) patients still own their
                // payments; the lists mark them (2026-10-17, as on web).
                'deleted_at' => $this->patientRegistration->deleted_at,
                // The service, only where it was loaded (the payments
                // report, 2026-10-17).
                ...($this->patientRegistration->relationLoaded('service') ? [
                    'service_name' => $this->patientRegistration->service?->name,
                ] : []),
            ] : null),
            // Student/employee discount for receipts and the report
            // (2026-10-25, by request): the full line and the short label;
            // null when the patient is not eligible.
            ...$this->discountFields(),
        ];
    }

    private function discountFields(): array
    {
        $registration = $this->relationLoaded('patientRegistration') ? $this->patientRegistration : null;
        if (! $registration?->discount_eligible) {
            return ['discount_line' => null, 'discount_label' => null, 'discount' => null];
        }

        $settings = ClinicSetting::current();
        $full = StudentDiscount::fullAmountFor($this->resource, $settings);

        return [
            'discount_line' => StudentDiscount::printLine($registration, (float) $this->amount, $full, (string) $settings->clinic_currency),
            'discount_label' => StudentDiscount::shortLabel($registration, (float) $this->amount, $full),
            // The amount, the discount and the amount after it, each on its
            // own row (2026-10-25, by request).
            'discount' => StudentDiscount::breakdown($registration, (float) $this->amount, $full),
        ];
    }
}
