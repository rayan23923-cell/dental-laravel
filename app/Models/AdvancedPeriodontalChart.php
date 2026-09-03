<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AdvancedPeriodontalChart extends Model
{
    protected $table = 'advanced_periodontal_charts';

    protected $fillable = [
        'task_instances_id',
        'task_id',
        'patient_id',
        'doctor_id',
        'patient_last_name',
        'patient_first_name',
        'patient_dob',
        'patient_gender',
        'exam_type',
        'chart_date',
        'notes',
        'senior_signature',
        'chart_data',
        // Merged in from PeriodontalChartForm (2026-09-03, by request) —
        // see the matching migration's own doc comment for why these and
        // not Patient Information/`chartGroups()`/the odontogram.
        'women_pregnancy', 'pregnancy_weeks', 'women_birth_control', 'women_nursing',
        'img_chief_complaint', 'img_medical_history',
        'img_smoker_yes', 'img_smoker_no', 'img_smoker_prev', 'img_smoker_stopped',
        'img_diabetes_yes', 'img_diabetes_no', 'img_diabetes_controlled_yes', 'img_diabetes_controlled_no', 'img_diabetes_lab',
        'img_brushing_once', 'img_brushing_twice', 'img_brushing_three', 'img_brushing_manual', 'img_brushing_powered',
        'img_interproximal_yes', 'img_interproximal_no', 'img_interproximal_type',
        'img_fam_hist_yes', 'img_fam_hist_no', 'img_fam_hist_details', 'img_prev_treatment',
        'img_tmj_yes', 'img_tmj_no', 'img_facial_yes', 'img_facial_no', 'img_facial_details',
        'img_missing_teeth', 'img_soft_tissue_yes', 'img_soft_tissue_no', 'img_soft_tissue_comments',
        'img_occlusal_yes', 'img_occlusal_no', 'img_mobile_yes', 'img_mobile_no', 'img_mobile_teeth',
        'img_caries_yes', 'img_caries_no', 'img_caries_teeth',
        'exam_bpe_ur', 'exam_bpe_ua', 'exam_bpe_ul', 'exam_bpe_lr', 'exam_bpe_la', 'exam_bpe_ll',
        'exam_radiograph_periapical', 'exam_radiograph_bitewing', 'exam_radiograph_panoramic', 'exam_radiograph_cbct',
        'exam_other_investigations', 'oral_hygiene', 'periodontal_condition',
        'diagnosis_pattern', 'diagnosis_stage', 'diagnosis_grade', 'diagnosis_status', 'diagnosis_risk_factors',
        'treatment_plan', 'treatment_plan_date', 'senior_doctor_name', 'approval_date', 'clinical_notes',
    ];

    protected function casts(): array
    {
        return [
            'patient_dob' => 'date',
            'chart_date' => 'date',
            'treatment_plan_date' => 'date',
            'approval_date' => 'date',
            'img_smoker_yes' => 'boolean',
            'img_smoker_no' => 'boolean',
            'img_smoker_prev' => 'boolean',
            'img_diabetes_yes' => 'boolean',
            'img_diabetes_no' => 'boolean',
            'img_diabetes_controlled_yes' => 'boolean',
            'img_diabetes_controlled_no' => 'boolean',
            'img_brushing_once' => 'boolean',
            'img_brushing_twice' => 'boolean',
            'img_brushing_three' => 'boolean',
            'img_brushing_manual' => 'boolean',
            'img_brushing_powered' => 'boolean',
            'img_interproximal_yes' => 'boolean',
            'img_interproximal_no' => 'boolean',
            'img_fam_hist_yes' => 'boolean',
            'img_fam_hist_no' => 'boolean',
            'img_tmj_yes' => 'boolean',
            'img_tmj_no' => 'boolean',
            'img_facial_yes' => 'boolean',
            'img_facial_no' => 'boolean',
            'img_soft_tissue_yes' => 'boolean',
            'img_soft_tissue_no' => 'boolean',
            'img_occlusal_yes' => 'boolean',
            'img_occlusal_no' => 'boolean',
            'img_mobile_yes' => 'boolean',
            'img_mobile_no' => 'boolean',
            'img_caries_yes' => 'boolean',
            'img_caries_no' => 'boolean',
            'exam_radiograph_periapical' => 'boolean',
            'exam_radiograph_bitewing' => 'boolean',
            'exam_radiograph_panoramic' => 'boolean',
            'exam_radiograph_cbct' => 'boolean',
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
}
