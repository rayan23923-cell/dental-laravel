<?php

namespace App\Models;

use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Appointment extends Model
{
    use LogsActivity;

    public $timestamps = false;

    protected $fillable = [
        'full_name',
        'patient_id',
        'patient_registration_id',
        'doctor_id',
        'case_sheet_doctor_id',
        'task_id',
        'appointment_date',
        'confirmed_by_accountant',
        'pinned',
    ];

    protected function casts(): array
    {
        return [
            'appointment_date' => 'date',
            'confirmed_by_accountant' => 'boolean',
            'pinned' => 'boolean',
        ];
    }

    /**
     * Legacy link — new appointments are created via `patientRegistration()`
     * below instead (see the migration that made `patient_id` nullable).
     * Kept for existing rows, which have no equivalent
     * `patient_registration_id` to migrate to.
     */
    public function patient(): BelongsTo
    {
        return $this->belongsTo(Patient::class);
    }

    public function patientRegistration(): BelongsTo
    {
        // Archived registrations still name their records (2026-10-12).
        return $this->belongsTo(PatientRegistration::class)->withTrashed();
    }

    /**
     * NOTE: appointments.doctor_id references users.id, not doctors.id —
     * confirmed via the source dump's FK constraint
     * (`appointments_ibfk_2 FOREIGN KEY (doctor_id) REFERENCES users (id)`).
     * Unlike every other clinical table in this app, appointments link to
     * the staff/users table here, not the doctors table.
     */
    public function doctor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'doctor_id');
    }

    public function task(): BelongsTo
    {
        return $this->belongsTo(Task::class);
    }

    /**
     * The student actually treating this patient's case sheet for this
     * task (`doctors.id`) — kept in sync by `AppointmentPatientSync`, not
     * a value the appointment form itself sets. Distinct from `doctor()`
     * above, which is the staff user who booked/manages the appointment.
     */
    public function caseSheetDoctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class, 'case_sheet_doctor_id');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }
}
