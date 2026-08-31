<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AdvancedPeriodontalChartResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'task_instances_id' => $this->task_instances_id,
            'task_id' => $this->task_id,
            'patient_id' => $this->patient_id,
            'doctor_id' => $this->doctor_id,
            'patient_last_name' => $this->patient_last_name,
            'patient_first_name' => $this->patient_first_name,
            'patient_dob' => $this->patient_dob,
            'exam_type' => $this->exam_type,
            'chart_date' => $this->chart_date,
            'notes' => $this->notes,
            'senior_signature' => $this->senior_signature,
            'chart_data' => $this->chart_data,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'name' => $this->doctor->name]),
        ];
    }
}
