<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class SurgeryImageResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'surgery_id' => $this->surgery_id,
            'image_url' => Storage::disk('public')->url($this->image_path),
            'image_type' => $this->image_type,
            'description' => $this->description,
            'uploaded_at' => $this->uploaded_at,
        ];
    }
}
