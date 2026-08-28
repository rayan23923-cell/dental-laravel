<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Surgery extends Model
{
    protected $table = 'surgeries';

    protected $fillable = [
        'task_instances_id',
        'task_id',
        'patient_id',
        'patient_name',
        'doctor_id',
        'student_name',
        'grade_group',
        'surgery_date',
        'surgery_date_field',
        'start_time',
        'staff_signature',
        'surgery_type',
        'chief_complaint',
        'cc_pain',
        'cc_swelling',
        'cc_others',
        'medical_history',
        'hpi_duration',
        'hpi_onset',
        'hpi_factors',
        'hpi_characteristics',
        'past_dental_history',
        'mh_blood_pressure',
        'mh_diabetes',
        'mh_heart',
        'mh_thyroid',
        'mh_bleeding',
        'mh_epilepsy',
        'mh_respiratory',
        'mh_git',
        'mh_liver',
        'mh_kidney',
        'mh_hiv',
        'mh_implants',
        'mh_hospitalization',
        'mh_hospitalization_details',
        'mh_smoking',
        'mh_smoking_amount',
        'mh_allergies',
        'mh_allergies_details',
        'mh_drugs',
        'mh_drugs_details',
        'mh_pregnant',
        'exam_extraoral',
        'exam_intraoral',
        'investigation',
        'diagnosis',
        'treatment_tooth',
        'selected_teeth',
        'surgical_procedure',
        'anesthesia_type',
        'duration_minutes',
        'complications',
        'postop_instructions',
        'follow_up_date',
        'status',
        'notes',
        'patient_phone',
        'patient_age',
        'patient_gender',
        'patient_address',
        'patient_occupation',
        'senior_doctor_name',
        'approval_date',
        'senior_signature',
    ];

    protected function casts(): array
    {
        return [
            'surgery_date' => 'datetime',
            'surgery_date_field' => 'date',
            'cc_pain' => 'boolean',
            'cc_swelling' => 'boolean',
            'follow_up_date' => 'date',
            'approval_date' => 'date',
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

    public function followUps(): HasMany
    {
        return $this->hasMany(SurgeryFollowUp::class);
    }

    public function images(): HasMany
    {
        return $this->hasMany(SurgeryImage::class);
    }

    public function medications(): HasMany
    {
        return $this->hasMany(SurgeryMedication::class);
    }
}
