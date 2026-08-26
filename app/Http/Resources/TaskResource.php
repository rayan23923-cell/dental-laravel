<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TaskResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'department_id' => $this->department_id,
            'case_sheet_type_id' => $this->case_sheet_type_id,
            'stage_id' => $this->stage_id,
            'required_per_doctor' => $this->required_per_doctor,
            'required_count' => $this->required_count,
            'done' => $this->done,
            'notes' => $this->notes,
            'grade' => $this->grade,
            'is_required' => (bool) $this->is_required,
            // The academic year this task belongs to; null = visible in all.
            'academic_session_id' => $this->academic_session_id,
            'department' => $this->whenLoaded('department', fn () => [
                'id' => $this->department->id,
                'name' => $this->department->name,
            ]),
            'case_sheet_type' => $this->whenLoaded('caseSheetType', fn () => [
                'id' => $this->caseSheetType->id,
                'name_en' => $this->caseSheetType->name_en,
                'name_ar' => $this->caseSheetType->name_ar,
            ]),
            'stage' => $this->whenLoaded('stage', fn () => $this->stage ? [
                'id' => $this->stage->id,
                'name' => $this->stage->name,
                // Additive — lets a "diagnosis" task picker (patient
                // registration) show which education type a task belongs
                // to without a second lookup call.
                'education_type' => $this->stage->relationLoaded('educationType') && $this->stage->educationType
                    ? ['id' => $this->stage->educationType->id, 'name' => $this->stage->educationType->name]
                    : null,
            ] : null),
            'instances' => TaskInstanceResource::collection($this->whenLoaded('instances')),
        ];
    }
}
