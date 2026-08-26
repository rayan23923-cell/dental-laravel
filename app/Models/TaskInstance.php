<?php

namespace App\Models;

use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TaskInstance extends Model
{
    use LogsActivity;

    public $timestamps = false;

    public const STATUSES = ['pending', 'assigned', 'completed'];

    protected $fillable = [
        'task_id',
        'doctor_id',
        'patient_registration_id',
        'status',
        'assigned_date',
        'completion_date',
        'notes',
        'grade',
        'assigned_by',
    ];

    protected function casts(): array
    {
        return [
            'assigned_date' => 'datetime',
            'completion_date' => 'datetime',
            'created_at' => 'datetime',
            'grade' => 'decimal:2',
        ];
    }

    public function task(): BelongsTo
    {
        return $this->belongsTo(Task::class);
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class);
    }

    public function assignedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_by');
    }

    /**
     * The specific patient visit this instance was started for — added
     * alongside the infectious-disease screening gate (2026-08-26).
     * Nullable: historical rows predate this link.
     */
    public function patientRegistration(): BelongsTo
    {
        return $this->belongsTo(PatientRegistration::class);
    }
}
