<?php

namespace App\Http\Resources;

use App\Support\StudentDiscount;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PatientRegistrationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'phone' => $this->phone,
            // Added 2026-08-28 for the case-sheet QR-autofill feature — the
            // scan flow only ever exposed name/phone before, but the doctor
            // form fields (age/sex/address/occupation) reception already
            // captured these at registration time, per
            // App\Support\CaseSheetPatientFieldMap.
            'age' => $this->age,
            'sex' => $this->sex,
            'address' => $this->address,
            'occupation' => $this->occupation,
            'service_id' => $this->service_id,
            'register_day_id' => $this->register_day_id,
            'task_id' => $this->task_id,
            // Student discount (2026-10-25), see App\Support\StudentDiscount.
            'discount_eligible' => (bool) $this->discount_eligible,
            'discount_type' => $this->discount_type,
            'discount_stage' => $this->discount_stage,
            'discount_workplace' => $this->discount_workplace,
            'discount_person_name' => $this->discount_person_name,
            // Care code (2026-11-01): the visit is free; see App\Support\SupportCodes.
            'supported' => $this->support_code_id !== null,
            'support_code' => $this->support_code_id ? \App\Models\SupportCode::whereKey($this->support_code_id)->value('code') : null,
            // What this patient pays for the service: its price, less the
            // student discount when eligible.
            // Once paid, the amounts recorded with the payment (2026-11-01, by
            // request: the price of the day, not today's price).
            'service_fee' => $this->whenLoaded('service', fn () => $this->servicePaidAndFull()[0]),
            // What the ticket prints about the discount (2026-10-25), e.g.
            // "طالب · المرحلة الرابعة — خصم 50% من 20,000".
            'discount_line' => $this->whenLoaded('service', fn () => ($pf = $this->servicePaidAndFull())[1] !== null
                ? StudentDiscount::printLine($this->resource, (float) $pf[0], (float) $pf[1], (string) \App\Models\ClinicSetting::current()->clinic_currency)
                : null),
            // The same as separate amounts for the ticket's rows (2026-10-25):
            // {who, percent, full, paid}.
            'discount' => $this->whenLoaded('service', fn () => ($pf = $this->servicePaidAndFull())[1] !== null
                ? StudentDiscount::breakdown($this->resource, (float) $pf[0], (float) $pf[1])
                : null),
            'screening_status' => $this->screening_status,
            'screening_reused_from' => $this->screening_reused_from,
            // Who recorded the lab result and when (2026-10-17), and the
            // date of the earlier test a reused result came from — what
            // the web lab page and its printed slip show.
            'screening_checked_at' => $this->screening_checked_at,
            'screening_checked_by' => $this->whenLoaded('screeningCheckedBy', fn () => $this->screeningCheckedBy ? [
                'id' => $this->screeningCheckedBy->id,
                'full_name' => $this->screeningCheckedBy->full_name,
            ] : null),
            'screening_reused_from_checked_at' => $this->whenLoaded(
                'screeningReusedFrom',
                fn () => $this->screeningReusedFrom?->screening_checked_at,
            ),
            'service' => $this->whenLoaded('service', fn () => $this->service ? [
                'id' => $this->service->id,
                'name' => $this->service->name,
                'price' => $this->service->price !== null ? (float) $this->service->price : null,
                'student_discount_percent' => (float) ($this->service->student_discount_percent ?? 50),
            ] : null),
            'register_day' => $this->whenLoaded('registerDay', fn () => $this->registerDay ? [
                'id' => $this->registerDay->id,
                'name' => $this->registerDay->name,
            ] : null),
            'task' => $this->whenLoaded('task', fn () => $this->task ? [
                'id' => $this->task->id,
                'title' => $this->task->title,
                'stage_name' => $this->task->stage?->name,
                'education_type_name' => $this->task->stage?->educationType?->name,
            ] : null),
            'created_at' => $this->created_at,
        ];
    }

    /**
     * [what the patient pays, the undiscounted price] for the service: from
     * the recorded payment once paid (2026-11-01), else today's price.
     *
     * @return array{0: ?float, 1: ?float}
     */
    private function servicePaidAndFull(): array
    {
        if (! $this->service) {
            return [null, null];
        }

        if ($this->support_code_id) {
            return [0.0, $this->service->price !== null ? (float) $this->service->price : null];
        }

        if ($this->resource->exists && ($recorded = StudentDiscount::recorded($this->resource, \App\Models\Payment::TYPE_SERVICE))) {
            return $recorded;
        }

        return [
            StudentDiscount::servicePrice($this->service, (bool) $this->discount_eligible),
            $this->service->price !== null ? (float) $this->service->price : null,
        ];
    }
}
