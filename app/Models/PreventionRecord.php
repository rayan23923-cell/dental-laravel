<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PreventionRecord extends Model
{
    protected $table = 'prevention_records';

    protected $fillable = [
        'doctor_id',
        'task_instances_id',
        'task_id',
        'patient_data',
        'examination_data',
        'supervisor_notes',
        'supervisor_signature',
    ];

    protected function casts(): array
    {
        return [
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
