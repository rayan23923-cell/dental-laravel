<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

/**
 * A photo of a task's paper case sheet (2026-10-13, by request), on the
 * `public` disk under `task-forms/{task_instance_id}/`. Added from the
 * computer, from the doctor's own phone, or sent by the paired phone; see
 * App\Http\Controllers\TaskInstanceAttachmentController.
 */
class TaskInstanceAttachment extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = ['task_instance_id', 'path', 'size', 'uploaded_by_user_id', 'uploaded_by_doctor_id'];

    protected static function booted(): void
    {
        static::deleted(fn (self $attachment) => Storage::disk('public')->delete($attachment->path));
    }

    public function taskInstance(): BelongsTo
    {
        return $this->belongsTo(TaskInstance::class);
    }

    public function toView(): array
    {
        return [
            'id' => $this->id,
            'url' => Storage::disk('public')->url($this->path),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
