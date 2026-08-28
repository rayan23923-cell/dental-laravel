<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TaskInstanceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'task_id' => $this->task_id,
            'doctor_id' => $this->doctor_id,
            'status' => $this->status,
            'assigned_date' => $this->assigned_date,
            'completion_date' => $this->completion_date,
            'notes' => $this->notes,
            'grade' => $this->grade,
            'assigned_by' => $this->assigned_by,
            // "شكرا، تم توثيقه ورقياً" (2026-08-28) — purely informational,
            // never gates the electronic case-sheet flow. Null/null means
            // "not confirmed on paper," not "unknown" — no whenLoaded()
            // needed, these are plain columns on this same row.
            'paper_case_sheet_confirmed_by' => $this->paper_case_sheet_confirmed_by,
            'paper_case_sheet_confirmed_at' => $this->paper_case_sheet_confirmed_at,
            // Both gated the same way, at the controller (only eager-loaded
            // when the viewer is authorized — see
            // `App\Support\TaskInstanceVisibility`) — `whenLoaded` then
            // naturally omits them for an unauthorized viewer rather than
            // sending the data and hiding it client-side only.
            'doctor' => $this->whenLoaded('doctor', fn () => [
                'id' => $this->doctor->id,
                'name' => $this->doctor->name,
                'username' => $this->doctor->username,
            ]),
            'assigned_by_name' => $this->whenLoaded('assignedBy', fn () => $this->assignedBy?->full_name),
            // department/case_sheet_type: TaskInstanceController::mine()/show()
            // already eager-load task.department and task.caseSheetType for
            // this exact purpose (the mobile task list needs to show which
            // department/sheet a task is), but this resource was dropping
            // them — additive fix, the two new keys are simply absent
            // (whenLoaded) for any caller that doesn't eager-load them.
            'task' => $this->whenLoaded('task', fn () => [
                'id' => $this->task->id,
                'title' => $this->task->title,
                // relationLoaded(), not whenLoaded() — that's a JsonResource
                // method, not an Eloquent Model one; $this->task is a plain
                // Task model here.
                'department' => $this->task->relationLoaded('department') && $this->task->department ? [
                    'id' => $this->task->department->id,
                    'name' => $this->task->department->name,
                ] : null,
                'case_sheet_type' => $this->task->relationLoaded('caseSheetType') && $this->task->caseSheetType ? [
                    'id' => $this->task->caseSheetType->id,
                    'name_en' => $this->task->caseSheetType->name_en,
                    'name_ar' => $this->task->caseSheetType->name_ar,
                ] : null,
            ]),
        ];
    }
}
