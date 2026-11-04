<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A refused attempt to link a patient to a case sheet (2026-11-04, by
 * request): see App\Support\CasePatientLinks::recordAttempt().
 */
class CasePatientLinkAttempt extends Model
{
    protected $fillable = [
        'patient_registration_id', 'doctor_id', 'task_id', 'linked_doctor_id', 'linked_task_id', 'reason', 'method', 'ip',
    ];

    public function registration(): BelongsTo
    {
        return $this->belongsTo(PatientRegistration::class, 'patient_registration_id')->withTrashed();
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class)->withTrashed();
    }

    public function task(): BelongsTo
    {
        return $this->belongsTo(Task::class)->withTrashed();
    }

    public function linkedDoctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class, 'linked_doctor_id')->withTrashed();
    }

    public function linkedTask(): BelongsTo
    {
        return $this->belongsTo(Task::class, 'linked_task_id')->withTrashed();
    }
}
