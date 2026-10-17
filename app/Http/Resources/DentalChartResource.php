<?php

namespace App\Http\Resources;

use App\Support\CaseSheetDoctor;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DentalChartResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'patient_id' => $this->patient_id,
            'patient_phone' => $this->patient_phone,
            'patient_age' => $this->patient_age,
            'patient_sex' => $this->patient_sex,
            'patient_address' => $this->patient_address,
            'patient_occupation' => $this->patient_occupation,
            'doctor_id' => $this->doctor_id,
            // The sheet's doctor, or its task case's (2026-10-15, as the web's
            // linkedDoctor) — shown as a name on the form. Not on lists (a query per row).
            'linked_doctor' => $this->unless($request->routeIs('*.index'), fn () => CaseSheetDoctor::linked($this->doctor_id, $this->task_instances_id)),
            'task_instances_id' => $this->task_instances_id,
            'task_id' => $this->task_id,
            'chart_type' => $this->chart_type,
            'visit_date' => $this->visit_date,
            'notes' => $this->notes,
            'chief_complaint' => $this->chief_complaint,
            'history_of_complaint' => $this->history_of_complaint,
            'oral_hygiene' => $this->oral_hygiene,
            'periodontal_condition' => $this->periodontal_condition,
            'non_vital_teeth' => $this->non_vital_teeth,
            'missing_teeth' => $this->missing_teeth,
            'crown_bridge_teeth' => $this->crown_bridge_teeth,
            'tooth_data' => $this->tooth_data,
            'endodontics_data' => $this->endodontics_data,
            'treatment_plan_date' => $this->treatment_plan_date,
            'treatment_plan_notes' => $this->treatment_plan_notes,
            'senior_doctor_name' => $this->senior_doctor_name,
            // Real gap found and fixed alongside the validation-rule gap in
            // Api\DentalChartController::validateChart() — this resource
            // never exposed the value at all, so even once a save worked a
            // client had no way to read it back (e.g. to show what's
            // already there before editing).
            'senior_signature' => $this->senior_signature,
            'doctor' => $this->whenLoaded('doctor', fn () => [
                'id' => $this->doctor->id,
                'name' => $this->doctor->name,
            ]),
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
        ];
    }
}
