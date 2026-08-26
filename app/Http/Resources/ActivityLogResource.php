<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ActivityLogResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'user_id' => $this->user_id,
            'username' => $this->username,
            'user_role' => $this->user_role,
            'action' => $this->action,
            'module' => $this->module,
            'description' => $this->description,
            'record_id' => $this->record_id,
            'created_at' => $this->created_at,
        ];
    }
}
