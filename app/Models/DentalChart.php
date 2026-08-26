<?php

namespace App\Models;

use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class DentalChart extends Model
{
    use LogsActivity;

    protected $fillable = [
        'patient_id',
        'patient_phone',
        'patient_age',
        'patient_sex',
        'patient_address',
        'patient_occupation',
        'doctor_id',
        'task_instances_id',
        'chart_type',
        'visit_date',
        'notes',
        'endodontics_data',
        'chief_complaint',
        'history_of_complaint',
        'oral_hygiene',
        'periodontal_condition',
        'non_vital_teeth',
        'missing_teeth',
        'crown_bridge_teeth',
        'tooth_data',
        'treatment_plan_date',
        'treatment_plan_notes',
        'senior_doctor_name',
        'senior_signature',
    ];

    protected function casts(): array
    {
        return [
            'visit_date' => 'datetime',
            'treatment_plan_date' => 'date',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
            'tooth_data' => 'array',
            'endodontics_data' => 'array',
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

    public function followUps(): HasMany
    {
        return $this->hasMany(DentalFollowUp::class);
    }

    public function toothConditions(): HasMany
    {
        return $this->hasMany(ToothCondition::class);
    }

    public function toothTreatments(): HasMany
    {
        return $this->hasMany(ToothTreatment::class);
    }

    public function treatmentPlans(): HasMany
    {
        return $this->hasMany(TreatmentPlan::class, 'chart_id');
    }
}
