<?php

namespace App\Http\Resources;

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
            'screening_status' => $this->screening_status,
            'screening_reused_from' => $this->screening_reused_from,
            'service' => $this->whenLoaded('service', fn () => $this->service ? [
                'id' => $this->service->id,
                'name' => $this->service->name,
                'price' => $this->service->price !== null ? (float) $this->service->price : null,
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
}
