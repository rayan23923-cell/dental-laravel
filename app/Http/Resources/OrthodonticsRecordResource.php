<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrthodonticsRecordResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'doctor_id' => $this->doctor_id,
            'task_instances_id' => $this->task_instances_id,
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
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'name' => $this->doctor->name]),
        ];
    }
}
