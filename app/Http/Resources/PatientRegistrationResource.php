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
            'service_id' => $this->service_id,
            'register_day_id' => $this->register_day_id,
            'task_id' => $this->task_id,
            'screening_status' => $this->screening_status,
            'service' => $this->whenLoaded('service', fn () => $this->service ? [
                'id' => $this->service->id,
                'name' => $this->service->name,
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
