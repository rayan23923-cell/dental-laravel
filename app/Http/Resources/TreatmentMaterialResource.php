<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TreatmentMaterialResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'tooth_treatment_id' => $this->tooth_treatment_id,
            'material_name' => $this->material_name,
            'material_type' => $this->material_type,
            'quantity' => $this->quantity,
            'unit' => $this->unit,
            'cost' => $this->cost,
            'notes' => $this->notes,
            'created_at' => $this->created_at,
        ];
    }
}
