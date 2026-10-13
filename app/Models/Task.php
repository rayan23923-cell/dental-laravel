<?php

namespace App\Models;

use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Task extends Model
{
    use LogsActivity;

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
        });
    }

    protected function casts(): array
    {
        return [
            'done' => 'boolean',
            'grade' => 'decimal:2',
            'is_required' => 'boolean',
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
