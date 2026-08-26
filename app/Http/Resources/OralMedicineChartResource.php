<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OralMedicineChartResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'doctor_id' => $this->doctor_id,
            'task_instances_id' => $this->task_instances_id,
            'case_no' => $this->case_no,
            'visit_date' => $this->visit_date,
            'patient_id' => $this->patient_id,
            'patient_age' => $this->patient_age,
            'patient_sex' => $this->patient_sex,
            'patient_address' => $this->patient_address,
            'patient_occupation' => $this->patient_occupation,
            'patient_phone' => $this->patient_phone,
            'chief_complaint' => $this->chief_complaint,
            'past_medical_history' => $this->past_medical_history,
            'surgical_history' => $this->surgical_history,
            'family_history' => $this->family_history,
            'social_history' => $this->social_history,
            'clinical_examination' => $this->clinical_examination,
            'extraoral_intraoral_examination' => $this->extraoral_intraoral_examination,
            'present_teeth' => $this->present_teeth,
            'teeth_requiring_treatment' => $this->teeth_requiring_treatment,
            'jaws_teeth_relations' => $this->jaws_teeth_relations,
            'history_of_complaint' => $this->history_of_complaint,
            'investigations_diagnosis' => $this->investigations_diagnosis,
            'student_visits' => $this->student_visits,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'doctor' => $this->whenLoaded('doctor', fn () => ['id' => $this->doctor->id, 'name' => $this->doctor->name]),
        ];
    }
}
