<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AdvancedPeriodontalChart extends Model
{
    protected $table = 'advanced_periodontal_charts';

    protected $fillable = [
        'task_instances_id',
        'task_id',
        'patient_id',
        'doctor_id',
        'patient_last_name',
        'patient_first_name',
        'patient_dob',
        'exam_type',
        'chart_date',
        'notes',
        'senior_signature',
        'chart_data',
    ];

    protected function casts(): array
    {
        return [
            'patient_dob' => 'date',
            'chart_date' => 'date',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class);
    }

    public function taskInstance(): BelongsTo
    {
        return $this->belongsTo(TaskInstance::class, 'task_instances_id');
    }

    /** Set only for a pre-instance draft — see `CaseSheetResolver::existingDraftRecordId()`. */
    public function task(): BelongsTo
    {
        return $this->belongsTo(Task::class);
    }

    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }
}
