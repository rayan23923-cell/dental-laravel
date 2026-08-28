<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class OrthodonticsRecord extends Model
{
    protected $table = 'orthodontics_records';

    protected $fillable = [
        'doctor_id',
        'task_instances_id',
        'task_id',
        'student_name',
        'group_name',
        'supervised_by',
        'patient_name',
        'patient_age',
        'patient_sex',
        'patient_address',
        'patient_phone',
        'referral_date',
        'referred_from',
        'examination_data',
        'supervisor_notes',
        'supervisor_signature',
    ];

    protected function casts(): array
    {
        return [
            'referral_date' => 'date',
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
}
