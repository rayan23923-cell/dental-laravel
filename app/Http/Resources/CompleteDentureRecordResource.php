<?php

namespace App\Http\Resources;

use App\Support\CaseSheetGrades;
use App\Support\CompleteDentureForm;
use App\Support\CaseSheetDoctor;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CompleteDentureRecordResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'doctor_id' => $this->doctor_id,
            // The sheet's doctor, or its task case's (2026-10-15, as the web's
            // linkedDoctor) — shown as a name on the form. Not on lists (a query per row).
            'linked_doctor' => $this->unless($request->routeIs('*.index'), fn () => CaseSheetDoctor::linked($this->doctor_id, $this->task_instances_id)),
            'task_instances_id' => $this->task_instances_id,
            // Each grade's max — the linked task's step max, else 10 (2026-10-15).
            'stage_maxes' => CaseSheetGrades::maxes(CompleteDentureForm::stages(), false, $this->task_instances_id),
            'task_id' => $this->task_id,
            'student_name' => $this->student_name,
            'patient_name' => $this->patient_name,
            'group_name' => $this->group_name,
            'age' => $this->age,
            'sex' => $this->sex,
            'telephone' => $this->telephone,
            'occupation' => $this->occupation,
            'address' => $this->address,
            'first_time' => $this->first_time,
            'medical_history' => $this->medical_history,
            'dental_extraction_reason' => $this->dental_extraction_reason,
            'dentist_visit_regular' => $this->dentist_visit_regular,
            'last_tooth_extracted' => $this->last_tooth_extracted,
            'last_tooth_extracted_teeth' => $this->last_tooth_extracted_teeth,
            'complete_denture_reason' => $this->complete_denture_reason,
            'partial_denture_reason' => $this->partial_denture_reason,
            'previous_complete_denture' => $this->previous_complete_denture,
            'previous_partial_denture' => $this->previous_partial_denture,
            'not_using_reason' => $this->not_using_reason,
            'new_denture_reason' => $this->new_denture_reason,
            'old_denture_retention' => $this->old_denture_retention,
            'old_denture_stability' => $this->old_denture_stability,
            'old_denture_centric' => $this->old_denture_centric,
            'old_denture_vertical' => $this->old_denture_vertical,
            'old_denture_appearance' => $this->old_denture_appearance,
            'old_denture_comfort' => $this->old_denture_comfort,
            'facial_muscle_tone' => $this->facial_muscle_tone,
            'face_form' => $this->face_form,
            'angles_jaw_classification' => $this->angles_jaw_classification,
            'vertical_dimensions_rest' => $this->vertical_dimensions_rest,
            'ridge_form_upper' => $this->ridge_form_upper,
            'ridge_form_lower' => $this->ridge_form_lower,
            'mucosa_upper' => $this->mucosa_upper,
            'mucosa_lower' => $this->mucosa_lower,
            'palate_depth' => $this->palate_depth,
            'tongue_size' => $this->tongue_size,
            'bony_exostosis' => $this->bony_exostosis,
            'teeth_to_extract' => $this->teeth_to_extract,
            'tmj_disorder' => $this->tmj_disorder,
            'muscles_mastication' => $this->muscles_mastication,
            'facial_tissue' => $this->facial_tissue,
            'missing_teeth' => $this->missing_teeth,
            'soft_tissue_condition' => $this->soft_tissue_condition,
            'abnormal_lesion' => $this->abnormal_lesion,
            'abutments_mobility' => $this->abutments_mobility,
            'preprosthetic_treatment' => $this->preprosthetic_treatment,
            'diagnosis_starting' => $this->diagnosis_starting,
            'diagnosis_instructor_signature' => $this->diagnosis_instructor_signature,
            'stage_preliminary_signature' => $this->stage_preliminary_signature,
            'stage_preliminary_date' => $this->stage_preliminary_date,
            'stage_preliminary_grade' => $this->stage_preliminary_grade,
            'stage_surveying_signature' => $this->stage_surveying_signature,
            'stage_surveying_date' => $this->stage_surveying_date,
            'stage_surveying_grade' => $this->stage_surveying_grade,
            'stage_final_signature' => $this->stage_final_signature,
            'stage_final_date' => $this->stage_final_date,
            'stage_final_grade' => $this->stage_final_grade,
            'stage_jawrel_signature' => $this->stage_jawrel_signature,
            'stage_jawrel_date' => $this->stage_jawrel_date,
            'stage_jawrel_grade' => $this->stage_jawrel_grade,
            'stage_trial_signature' => $this->stage_trial_signature,
            'stage_trial_date' => $this->stage_trial_date,
            'stage_trial_grade' => $this->stage_trial_grade,
            'stage_flasking_signature' => $this->stage_flasking_signature,
            'stage_flasking_date' => $this->stage_flasking_date,
            'stage_flasking_grade' => $this->stage_flasking_grade,
            'stage_cd_signature' => $this->stage_cd_signature,
            'stage_cd_date' => $this->stage_cd_date,
            'stage_cd_grade' => $this->stage_cd_grade,
            'stage_adjust1_signature' => $this->stage_adjust1_signature,
            'stage_adjust1_date' => $this->stage_adjust1_date,
            'stage_adjust1_grade' => $this->stage_adjust1_grade,
            'stage_finaleval_signature' => $this->stage_finaleval_signature,
            'stage_finaleval_date' => $this->stage_finaleval_date,
            'stage_finaleval_grade' => $this->stage_finaleval_grade,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'name' => $this->doctor->name]),
        ];
    }
}
