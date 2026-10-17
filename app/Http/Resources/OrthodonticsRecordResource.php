<?php

namespace App\Http\Resources;

use App\Support\CaseSheetDoctor;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrthodonticsRecordResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'doctor_id' => $this->doctor_id,
            // The sheet's doctor, or its task case's (2026-10-15, as the web's
            // linkedDoctor) — shown as a name on the form. Not on lists (a query per row).
            'linked_doctor' => $this->unless($request->routeIs('*.index'), fn () => CaseSheetDoctor::linked($this->doctor_id, $this->task_instances_id)),
            'task_instances_id' => $this->task_instances_id,
            'task_id' => $this->task_id,
            'student_name' => $this->student_name,
            'group_name' => $this->group_name,
            'supervised_by' => $this->supervised_by,
            'patient_name' => $this->patient_name,
            'patient_age' => $this->patient_age,
            'patient_sex' => $this->patient_sex,
            'patient_address' => $this->patient_address,
            'patient_phone' => $this->patient_phone,
            'referral_date' => $this->referral_date,
            'referred_from' => $this->referred_from,
            'examination_data' => $this->examination_data,
            'supervisor_notes' => $this->supervisor_notes,
            'supervisor_signature' => $this->supervisor_signature,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'name' => $this->doctor->name]),
        ];
    }
}
