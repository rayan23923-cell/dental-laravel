<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * `patients_simple` — the reception-desk "register a new patient" table:
 * name, phone, a chosen service, and the day it's offered. **Deliberately
 * separate from `App\Models\Patient`** (table `patients`), which tracks a
 * patient through a doctor/task/stage workflow — the two were never the
 * same concept in the legacy app (`dental_clinics2`) either, and the
 * current schema keeps them as two unrelated tables. Confirmed via a
 * dedicated research pass before building this (2026-08-21): this is
 * what the "register a new patient with a service and day" request maps
 * to, not the existing `Patient`/`PatientController` module.
 *
 * `note`/`day` (plain text) are the legacy columns — real historical rows
 * already in this table use them, with the day stored as either an Arabic
 * name or a numeric id depending on which of the legacy app's two entry
 * points wrote the row, and the service concatenated into `note` as
 * `'نوع الخدمة: {service} - {note}'`. New code uses `service_id`/
 * `register_day_id` instead (see the migration that added them) and never
 * writes to `note`/`day`.
 */
class PatientRegistration extends Model
{
    // Deleting archives (2026-10-12): `deleted_at` is stamped and the row
    // drops out of every list, but its payments still resolve to it.
    use SoftDeletes;

    protected $table = 'patients_simple';

    public $timestamps = false;

    protected $fillable = [
        'name',
        'phone',
        'age',
        'sex',
        'address',
        'occupation',
        'service_id',
        'register_day_id',
        'task_id',
        'screening_status',
        'screening_checked_by',
        'screening_checked_at',
        'screening_reused_from',
        // Student discount (2026-10-25), see App\Support\StudentDiscount.
        'discount_eligible',
        // 'student' (optional stage) or 'employee' (optional workplace).
        'discount_type',
        'discount_stage',
        'discount_workplace',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
            'discount_eligible' => 'boolean',
        ];
    }

    public function service(): BelongsTo
    {
        return $this->belongsTo(Service::class);
    }

    public function registerDay(): BelongsTo
    {
        return $this->belongsTo(RegisterDay::class, 'register_day_id');
    }

    /**
     * "التشخيص" — a plain informational pick at registration time, not a
     * workflow link: doesn't gate or filter anything, just records which
     * task the desk clerk associated with this registration and lets the
     * UI show its stage/education type. See the migration that added it.
     */
    public function task(): BelongsTo
    {
        return $this->belongsTo(Task::class);
    }

    /**
     * Payments taken against this registration at the desk (ticket-QR
     * flow). See the migration that added `payments.patient_registration_id`.
     */
    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class, 'patient_registration_id');
    }

    /** Case-sheet work started for this visit (`TaskInstance`). */
    public function taskInstances(): HasMany
    {
        return $this->hasMany(TaskInstance::class, 'patient_registration_id');
    }

    /**
     * The lab/reception staff member who last recorded a screening result
     * (`PatientScreeningGate`/`confirmScreening()`). No FK, same reasoning
     * as `TaskInstance::assignedBy()`.
     */
    /** The earlier registration whose clear lab result this one reuses. */
    public function screeningReusedFrom(): BelongsTo
    {
        return $this->belongsTo(self::class, 'screening_reused_from');
    }

    public function screeningCheckedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'screening_checked_by');
    }
}
