<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProsthodonticsRecord extends Model
{
    protected $table = 'prosthodontics_records';

    protected $fillable = [
        'task_instances_id',
        'task_id',
        'doctor_id',
        'student_name',
        'patient_name',
        'patient_phone',
        'group_name',
        'age',
        'sex',
        'telephone',
        'occupation',
        'address',
        'first_time',
        'medical_history',
        'dental_extraction_reason',
        'dentist_visit_regular',
        'partial_denture_reason',
        'previous_partial_denture',
        'not_using_reason',
        'tmj_disorder',
        'muscles_mastication',
        'facial_tissue',
        'missing_teeth',
        'caries_teeth',
        'soft_tissue_condition',
        'abnormal_lesion',
        'abutments_mobility',
        'teeth_extraction',
        'preprosthetic_treatment',
        'diagnosis_starting',
        'diagnosis_instructor_signature',
        'diagnosis_date',
        'diagnosis_grade',
        'stage_preliminary_signature',
        'stage_preliminary_date',
        'stage_preliminary_grade',
        'stage_surveying_signature',
        'stage_surveying_date',
        'stage_surveying_grade',
        'stage_final_signature',
        'stage_final_date',
        'stage_final_grade',
        'stage_jawrel_signature',
        'stage_jawrel_date',
        'stage_jawrel_grade',
        'stage_trial_signature',
        'stage_trial_date',
        'stage_trial_grade',
        'stage_flasking_signature',
        'stage_flasking_date',
        'stage_flasking_grade',
        'stage_rpd_signature',
        'stage_rpd_date',
        'stage_rpd_grade',
        'stage_adjust1_signature',
        'stage_adjust1_date',
        'stage_adjust1_grade',
        'stage_finaleval_signature',
        'stage_finaleval_date',
        'stage_finaleval_grade',
        'tooth_chart_data',
    ];

    protected function casts(): array
    {
        return [
            'diagnosis_date' => 'date',
            'stage_preliminary_date' => 'date',
            'stage_surveying_date' => 'date',
            'stage_final_date' => 'date',
            'stage_jawrel_date' => 'date',
            'stage_trial_date' => 'date',
            'stage_flasking_date' => 'date',
            'stage_rpd_date' => 'date',
            'stage_adjust1_date' => 'date',
            'stage_finaleval_date' => 'date',
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
