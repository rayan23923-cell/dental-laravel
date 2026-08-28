<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CompleteDentureRecord extends Model
{
    protected $table = 'complete_denture_records';

    protected $fillable = [
        'doctor_id',
        'task_instances_id',
        'task_id',
        'student_name',
        'patient_name',
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
        'last_tooth_extracted',
        'last_tooth_extracted_teeth',
        'complete_denture_reason',
        'partial_denture_reason',
        'previous_complete_denture',
        'previous_partial_denture',
        'not_using_reason',
        'new_denture_reason',
        'old_denture_retention',
        'old_denture_stability',
        'old_denture_centric',
        'old_denture_vertical',
        'old_denture_appearance',
        'old_denture_comfort',
        'facial_muscle_tone',
        'face_form',
        'angles_jaw_classification',
        'vertical_dimensions_rest',
        'ridge_form_upper',
        'ridge_form_lower',
        'mucosa_upper',
        'mucosa_lower',
        'palate_depth',
        'tongue_size',
        'bony_exostosis',
        'teeth_to_extract',
        'tmj_disorder',
        'muscles_mastication',
        'facial_tissue',
        'missing_teeth',
        'soft_tissue_condition',
        'abnormal_lesion',
        'abutments_mobility',
        'preprosthetic_treatment',
        'diagnosis_starting',
        'diagnosis_instructor_signature',
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
        'stage_cd_signature',
        'stage_cd_date',
        'stage_cd_grade',
        'stage_adjust1_signature',
        'stage_adjust1_date',
        'stage_adjust1_grade',
        'stage_finaleval_signature',
        'stage_finaleval_date',
        'stage_finaleval_grade',
    ];

    protected function casts(): array
    {
        return [
            'stage_preliminary_date' => 'date',
            'stage_surveying_date' => 'date',
            'stage_final_date' => 'date',
            'stage_jawrel_date' => 'date',
            'stage_trial_date' => 'date',
            'stage_flasking_date' => 'date',
            'stage_cd_date' => 'date',
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
