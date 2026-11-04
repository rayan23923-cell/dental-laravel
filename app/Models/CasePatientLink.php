<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A patient's registration linked to one case (2026-11-04, by request):
 * the doctor's draft for a task (doctor + task, no instance yet) or a
 * started task instance. See App\Support\CasePatientLinks.
 */
class CasePatientLink extends Model
{
    protected $fillable = [
        'patient_registration_id', 'doctor_id', 'task_id', 'task_instance_id', 'department_id', 'method',
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

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }
}
