<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class OralMedicineChart extends Model
{
    protected $table = 'oral_medicine_charts';

    protected $fillable = [
        'doctor_id',
        'task_instances_id',
        'task_id',
        'case_no',
        'visit_date',
        'patient_id',
        'patient_age',
        'patient_sex',
        'patient_address',
        'patient_occupation',
        'patient_phone',
        'chief_complaint',
        'past_medical_history',
        'surgical_history',
        'family_history',
        'social_history',
        'clinical_examination',
        'extraoral_intraoral_examination',
        'present_teeth',
        'teeth_requiring_treatment',
        'jaws_teeth_relations',
        'history_of_complaint',
        'investigations_diagnosis',
        'student_visits',
        'supervisor_notes',
        'supervisor_signature',
    ];

    protected function casts(): array
    {
        return [
            'visit_date' => 'date',
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
