<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PreventionRecordResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'doctor_id' => $this->doctor_id,
            'task_instances_id' => $this->task_instances_id,
            'task_id' => $this->task_id,
            'patient_data' => $this->patient_data,
            'examination_data' => $this->examination_data,
            'supervisor_notes' => $this->supervisor_notes,
            'supervisor_signature' => $this->supervisor_signature,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'name' => $this->doctor->name]),
        ];
    }
}
