<?php

namespace App\Models;

use App\Support\TaskScoring;
use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Task extends Model
{
    // Archived instead of deleted (2026-10-14, by request); see App\Support\LinkedRecords.
    use LogsActivity, SoftDeletes;

    public $timestamps = false;

    protected $fillable = [
        'department_id',
        'case_sheet_type_id',
        'stage_id',
        'title',
        'required_per_doctor',
        'done',
        'required_count',
        'notes',
        'grade',
        'academic_session_id',
        'is_required',
        // Points-based requirements (2026-10-14); see App\Support\TaskScoring.
        'scoring',
    ];

    /**
     * `required_count` is the one per-doctor cap (2026-10-13, by request:
     * "المطلوب لكل طبيب" was dropped). The NOT NULL legacy column is kept
     * in step with it so nothing reading it disagrees.
     */
    protected static function booted(): void
    {
        static::saving(function (Task $task) {
            $task->required_per_doctor = (int) $task->required_count;

            // A task on the surgery sheet gets that sheet's steps when the
            // sheet is chosen (2026-10-19, by request); see TaskScoring::withSurgerySteps().
            if ((! $task->exists || $task->isDirty('case_sheet_type_id'))
                && CaseSheetType::whereKey($task->case_sheet_type_id)->value('type_code') === 'surgery') {
                $task->scoring = TaskScoring::withSurgerySteps($task->scoring);
            }
        });
    }

    protected function casts(): array
    {
        return [
            'done' => 'boolean',
            'grade' => 'decimal:2',
            'is_required' => 'boolean',
            'scoring' => 'array',
        ];
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function caseSheetType(): BelongsTo
    {
        return $this->belongsTo(CaseSheetType::class);
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function instances(): HasMany
    {
        return $this->hasMany(TaskInstance::class);
    }

    public function academicSession(): BelongsTo
    {
        return $this->belongsTo(AcademicSession::class);
    }

    /**
     * Mirrors `Service::days()` — see `RegisterDay::tasks()`'s docblock
     * for the full picture. Unrelated to `stage`/`department` above,
     * which govern this task's clinical scope, not registration-desk
     * availability.
     */
    public function days(): BelongsToMany
    {
        return $this->belongsToMany(RegisterDay::class, 'register_day_task_map', 'task_id', 'day_id');
    }
}
