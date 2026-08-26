<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class DoctorResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'username' => $this->username,
            'email' => $this->email,
            'phone' => $this->phone,
            'profile_image_url' => $this->profile_image ? Storage::disk('public')->url($this->profile_image) : null,
            'education_type_id' => $this->education_type_id,
            'stage_id' => $this->stage_id,
            'nfc_tag_id' => $this->nfc_tag_id,
            'education_type' => $this->whenLoaded('educationType', fn () => [
                'id' => $this->educationType->id,
                'name' => $this->educationType->name,
            ]),
            'stage' => $this->whenLoaded('stage', fn () => [
                'id' => $this->stage->id,
                'name' => $this->stage->name,
            ]),
            // The academic year the doctor was enrolled in; null = visible
            // under every session.
            'academic_session_id' => $this->academic_session_id,
            // Null-guarded: the relation is loaded but empty for a
            // session-less doctor, and whenLoaded() still runs the closure.
            'academic_session' => $this->whenLoaded('academicSession', fn () => $this->academicSession ? [
                'id' => $this->academicSession->id,
                'name' => $this->academicSession->name,
            ] : null),
            // Only used by the roster PDF today (a doctor can belong to more
            // than one group, hence a list here rather than a single field).
            'groups' => $this->whenLoaded('groups', fn () => $this->groups->map(fn ($g) => [
                'id' => $g->id,
                'name' => $g->name,
            ])),
            'created_at' => $this->created_at,
        ];
    }
}
