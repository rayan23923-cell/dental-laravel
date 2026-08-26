<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TreatmentPlanResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'chart_id' => $this->chart_id,
            'plan_date' => $this->plan_date,
            'plan_notes' => $this->plan_notes,
            'mark' => $this->mark,
            'doctor_name' => $this->doctor_name,
            'signature' => $this->signature,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
        ];
    }
}
