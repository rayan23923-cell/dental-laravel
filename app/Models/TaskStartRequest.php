<?php

namespace App\Models;

use App\Support\CaseSheetResolver;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

/**
 * A doctor's request to start a task (2026-10-14, by request); see
 * App\Services\TaskStartRequests. The paper form's photo lives on the
 * `public` disk under `task-start-requests/`, and moves to the task
 * instance's attachments when the request is approved.
 */
class TaskStartRequest extends Model
{
    protected $fillable = [
        'doctor_id', 'task_id', 'form_type', 'photo_path', 'notes', 'status',
        'reviewed_by_user_id', 'reviewed_at', 'review_note', 'task_instance_id',
    ];

    protected function casts(): array
    {
        return ['reviewed_at' => 'datetime'];
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class)->withTrashed();
    }

    public function task(): BelongsTo
    {
        return $this->belongsTo(Task::class)->withTrashed();
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by_user_id');
    }

    /**
     * The electronic form to preview: the doctor's draft, or the started
     * instance's sheet once approved. [resource, record id] or null.
     *
     * @return array{0: string, 1: int}|null
     */
    public function caseSheetRecord(): ?array
    {
        if ($this->form_type !== 'electronic' || ! $this->task) {
            return null;
        }
        $resource = CaseSheetResolver::resourceForTask($this->task);
        $recordId = $this->task_instance_id
            ? CaseSheetResolver::existingRecordId($resource, $this->task_instance_id)
            : CaseSheetResolver::existingDraftRecordId($resource, $this->doctor_id, $this->task_id);

        return $recordId ? [$resource, (int) $recordId] : null;
    }

    public function toView(): array
    {
        $this->loadMissing(['doctor.stage', 'task.department', 'task.caseSheetType', 'reviewer']);

        return [
            'id' => $this->id,
            'status' => $this->status,
            'form_type' => $this->form_type,
            'notes' => $this->notes,
            'photo_url' => $this->photo_path ? Storage::disk('public')->url($this->photo_path) : null,
            // Web preview (print view) and, for the app, the sheet to open.
            'case_sheet_url' => ($sheet = $this->caseSheetRecord()) ? route('case-sheets.print', $sheet) : null,
            'case_sheet' => $sheet ? ['resource' => $sheet[0], 'record_id' => $sheet[1]] : null,
            'created_at' => $this->created_at?->toIso8601String(),
            'reviewed_at' => $this->reviewed_at?->toIso8601String(),
            'review_note' => $this->review_note,
            'reviewer' => $this->reviewer?->full_name,
            'task_instance_id' => $this->task_instance_id,
            'doctor' => [
                'id' => $this->doctor?->id,
                'name' => $this->doctor?->name,
                'stage' => $this->doctor?->stage?->name,
                'photo_url' => $this->doctor?->profile_image ? Storage::disk('public')->url($this->doctor->profile_image) : null,
            ],
            'task' => [
                'id' => $this->task?->id,
                'title' => $this->task?->title,
                'department' => $this->task?->department?->name,
                'case_sheet' => $this->task?->caseSheetType?->name_ar,
                'required_count' => (int) $this->task?->required_count,
            ],
        ];
    }
}
