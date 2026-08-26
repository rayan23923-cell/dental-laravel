<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SurgeryFollowUpResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'surgery_id' => $this->surgery_id,
            'follow_up_date' => $this->follow_up_date,
            'findings' => $this->findings,
            'patient_status' => $this->patient_status,
            'next_appointment' => $this->next_appointment,
            'notes' => $this->notes,
            'created_at' => $this->created_at,
        ];
    }
}
