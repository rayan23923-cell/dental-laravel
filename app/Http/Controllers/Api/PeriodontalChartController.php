<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PeriodontalChartResource;
use App\Models\Patient;
use App\Models\PeriodontalChart;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PeriodontalChartController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = PeriodontalChart::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return PeriodontalChartResource::collection($records)->response();
    }

    public function show(PeriodontalChart $record): JsonResponse
    {
        return (new PeriodontalChartResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_id'] = $this->resolvePatientId($data);

        $record = PeriodontalChart::create($data);

        return (new PeriodontalChartResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, PeriodontalChart $record): JsonResponse
    {
        $data = $this->validateRecord($request, true);
        $data['patient_id'] = $this->resolvePatientId($data, $record->patient_id);

        $record->update($data);

        return (new PeriodontalChartResource($record))->response();
    }

    /**
     * `periodontal_charts.patient_id` is an int FK while a case-sheet
     * client only ever collects a name — mirrors
     * `App\Http\Controllers\PeriodontalChartController::resolvePatientId()`
     * exactly (same pattern already ported to `Api\SurgeryController`, see
     * flutter_app/README.md, "Case sheet create"), so a record created
     * through either path stays joinable to a real `patients` row rather
     * than carrying an orphan id.
     */
    private function resolvePatientId(array $data, ?int $currentId = null): ?int
    {
        $name = trim($data['patient_name'] ?? '');
        if ($name === '') {
            return $currentId;
        }

        $query = Patient::where('name', $name);
        if (! empty($data['patient_phone'])) {
            $query->where('phone', $data['patient_phone']);
        }

        return ($query->first() ?? Patient::create([
            'name' => $name,
            'phone' => $data['patient_phone'] ?? null,
        ]))->id;
    }

    public function destroy(PeriodontalChart $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            // Not client-supplied — resolved server-side by
            // resolvePatientId() from patient_name (+ patient_phone), same
            // as Api\SurgeryController.
            'patient_id' => ['nullable', 'integer'],
            'doctor_id' => ['required', 'integer'],
            'patient_name' => ['nullable', 'string', 'max:255'],
            'patient_first_name' => ['nullable', 'string', 'max:255'],
            'patient_middle_name' => ['nullable', 'string', 'max:255'],
            'patient_surname' => ['nullable', 'string', 'max:255'],
            'patient_dob' => ['nullable', 'date'],
            'patient_marital_status' => ['nullable', 'string', 'max:255'],
            'chart_date' => ['required', 'date'],
            'chief_complaints' => ['nullable', 'string'],
            'history_present_illness' => ['nullable', 'string'],
            'med_general_health' => ['nullable', 'string'],
            'med_hospitalization' => ['nullable', 'string', 'max:255'],
            'med_hospitalization_reason' => ['nullable', 'string'],
            'med_medication' => ['nullable', 'string'],
            'med_others_disease' => ['nullable', 'string', 'max:255'],
            'med_osteoporosis' => ['nullable', 'string', 'max:255'],
            'med_malignancies' => ['nullable', 'string', 'max:255'],
            'med_git' => ['nullable', 'string', 'max:255'],
            'med_respiratory' => ['nullable', 'string', 'max:255'],
            'med_asthma' => ['nullable', 'string', 'max:255'],
            'med_epilepsy' => ['nullable', 'string', 'max:255'],
            'med_urinary' => ['nullable', 'string', 'max:255'],
            'med_skin_dis' => ['nullable', 'string', 'max:255'],
            'med_cva' => ['nullable', 'string', 'max:255'],
            'med_hiv' => ['nullable', 'string', 'max:255'],
            'med_diabetes' => ['nullable', 'string', 'max:255'],
            'med_hepatitis' => ['nullable', 'string', 'max:255'],
            'med_blood_pressure' => ['nullable', 'string', 'max:255'],
            'med_blood_dis' => ['nullable', 'string', 'max:255'],
            'med_heart_surgery' => ['nullable', 'string', 'max:255'],
            'med_disease_notes' => ['nullable', 'string'],
            'med_allergy_others' => ['nullable', 'string', 'max:255'],
            'med_allergy_food' => ['nullable', 'string', 'max:255'],
            'med_allergy_antibiotics' => ['nullable', 'string', 'max:255'],
            'med_allergy_aspirin' => ['nullable', 'string', 'max:255'],
            'med_allergy_local_anest' => ['nullable', 'string', 'max:255'],
            'med_allergy_notes' => ['nullable', 'string'],
            'med_women_pregnancy' => ['nullable', 'string', 'max:255'],
            'med_women_weeks' => ['nullable', 'string', 'max:255'],
            'med_women_pills' => ['nullable', 'string', 'max:255'],
            'med_women_nursing' => ['nullable', 'string', 'max:255'],
            'med_other_conditions' => ['nullable', 'string'],
            'dental_last_visit_date' => ['nullable', 'date'],
            'dental_last_visit_reason' => ['nullable', 'string'],
            'dental_complications' => ['nullable', 'string'],
            'dental_prev_perio_treatment' => ['nullable', 'string', 'max:255'],
            'dental_prev_perio_when' => ['nullable', 'string', 'max:255'],
            'dental_prev_perio_for' => ['nullable', 'string', 'max:255'],
            'oral_chemical_agent' => ['nullable', 'string', 'max:255'],
            'family_systemic_disease' => ['nullable', 'string', 'max:255'],
            'family_systemic_disease_details' => ['nullable', 'string'],
            'hist_smoker' => ['nullable', 'string', 'max:255'],
            'hist_smoker_previous' => ['nullable', 'boolean'],
            'hist_smoker_when_stopped' => ['nullable', 'string', 'max:255'],
            'hist_smoker_type' => ['nullable', 'string', 'max:255'],
            'hist_smoker_frequency' => ['nullable', 'string', 'max:255'],
            'hist_smoker_duration' => ['nullable', 'string', 'max:255'],
            'alcohol_consumption' => ['nullable', 'string', 'max:255'],
            'behavioural_habits' => ['nullable', 'string'],
            'dietary_habit' => ['nullable', 'string'],
            'hist_diabetes' => ['nullable', 'string', 'max:255'],
            'hist_diabetes_controlled' => ['nullable', 'string', 'max:255'],
            'hist_diabetes_lab' => ['nullable', 'string'],
            'hist_brushing_freq' => ['nullable', 'string', 'max:255'],
            'hist_brush_type' => ['nullable', 'string', 'max:255'],
            'hist_brushing_duration' => ['nullable', 'string', 'max:255'],
            'hist_interproximal' => ['nullable', 'string', 'max:255'],
            'hist_interproximal_details' => ['nullable', 'string'],
            'hist_family_perio' => ['nullable', 'string', 'max:255'],
            'hist_family_perio_details' => ['nullable', 'string'],
            'hist_previous_treatment' => ['nullable', 'string'],
            'exam_tmj_click' => ['nullable', 'string', 'max:255'],
            'exam_facial_asymmetry' => ['nullable', 'string', 'max:255'],
            'exam_facial_asymmetry_details' => ['nullable', 'string'],
            'exam_missing_teeth' => ['nullable', 'integer'],
            'exam_soft_tissue' => ['nullable', 'string', 'max:255'],
            'exam_soft_tissue_comments' => ['nullable', 'string'],
            'exam_occlusal_trauma' => ['nullable', 'string', 'max:255'],
            'exam_occlusal_trauma_details' => ['nullable', 'string'],
            'exam_mobile_teeth' => ['nullable', 'string', 'max:255'],
            'exam_mobile_teeth_which' => ['nullable', 'string'],
            'exam_caries' => ['nullable', 'string', 'max:255'],
            'exam_caries_teeth' => ['nullable', 'string'],
            'exam_bpe_ur' => ['nullable', 'string', 'max:255'],
            'exam_bpe_ua' => ['nullable', 'string', 'max:255'],
            'exam_bpe_ul' => ['nullable', 'string', 'max:255'],
            'exam_bpe_lr' => ['nullable', 'string', 'max:255'],
            'exam_bpe_la' => ['nullable', 'string', 'max:255'],
            'exam_bpe_ll' => ['nullable', 'string', 'max:255'],
            'exam_radiograph_periapical' => ['nullable', 'boolean'],
            'exam_radiograph_bitewing' => ['nullable', 'boolean'],
            'exam_radiograph_panoramic' => ['nullable', 'boolean'],
            'exam_radiograph_cbct' => ['nullable', 'boolean'],
            'exam_other_investigations' => ['nullable', 'string'],
            'oral_hygiene' => ['nullable', 'string'],
            'periodontal_condition' => ['nullable', 'string'],
            'notes' => ['nullable', 'string'],
            'diagnosis_pattern' => ['nullable', 'string', 'max:255'],
            'diagnosis_stage' => ['nullable', 'string', 'max:255'],
            'diagnosis_grade' => ['nullable', 'string', 'max:255'],
            'diagnosis_status' => ['nullable', 'string', 'max:255'],
            'diagnosis_risk_factors' => ['nullable', 'string'],
            'img_chief_complaint' => ['nullable', 'string'],
            'img_medical_history' => ['nullable', 'string'],
            'img_smoker_yes' => ['nullable', 'boolean'],
            'img_smoker_no' => ['nullable', 'boolean'],
            'img_smoker_prev' => ['nullable', 'boolean'],
            'img_smoker_stopped' => ['nullable', 'string', 'max:255'],
            'img_diabetes_yes' => ['nullable', 'boolean'],
            'img_diabetes_no' => ['nullable', 'boolean'],
            'img_diabetes_controlled_yes' => ['nullable', 'boolean'],
            'img_diabetes_controlled_no' => ['nullable', 'boolean'],
            'img_diabetes_lab' => ['nullable', 'string', 'max:255'],
            'img_brushing_once' => ['nullable', 'boolean'],
            'img_brushing_twice' => ['nullable', 'boolean'],
            'img_brushing_three' => ['nullable', 'boolean'],
            'img_brushing_manual' => ['nullable', 'boolean'],
            'img_brushing_powered' => ['nullable', 'boolean'],
            'img_interproximal_yes' => ['nullable', 'boolean'],
            'img_interproximal_no' => ['nullable', 'boolean'],
            'img_interproximal_type' => ['nullable', 'string', 'max:255'],
            'img_fam_hist_yes' => ['nullable', 'boolean'],
            'img_fam_hist_no' => ['nullable', 'boolean'],
            'img_fam_hist_details' => ['nullable', 'string'],
            'img_prev_treatment' => ['nullable', 'string'],
            'img_tmj_yes' => ['nullable', 'boolean'],
            'img_tmj_no' => ['nullable', 'boolean'],
            'img_facial_yes' => ['nullable', 'boolean'],
            'img_facial_no' => ['nullable', 'boolean'],
            'img_facial_details' => ['nullable', 'string'],
            'img_missing_teeth' => ['nullable', 'string', 'max:255'],
            'img_soft_tissue_yes' => ['nullable', 'boolean'],
            'img_soft_tissue_no' => ['nullable', 'boolean'],
            'img_soft_tissue_comments' => ['nullable', 'string'],
            'img_occlusal_yes' => ['nullable', 'boolean'],
            'img_occlusal_no' => ['nullable', 'boolean'],
            'img_mobile_yes' => ['nullable', 'boolean'],
            'img_mobile_no' => ['nullable', 'boolean'],
            'img_mobile_teeth' => ['nullable', 'string', 'max:255'],
            'img_caries_yes' => ['nullable', 'boolean'],
            'img_caries_no' => ['nullable', 'boolean'],
            'img_caries_teeth' => ['nullable', 'string', 'max:255'],
            'women_pregnancy' => ['nullable', 'string', 'max:255'],
            'pregnancy_weeks' => ['nullable', 'string', 'max:255'],
            'women_birth_control' => ['nullable', 'string', 'max:255'],
            'women_nursing' => ['nullable', 'string', 'max:255'],
            'clinical_notes' => ['nullable', 'string'],
            'treatment_plan' => ['nullable', 'string'],
            'treatment_plan_date' => ['nullable', 'date'],
            'senior_doctor_name' => ['nullable', 'string', 'max:255'],
            'approval_date' => ['nullable', 'date'],
            'senior_signature' => ['nullable', 'string'],
            'chart_data' => ['required', 'string'],
            'patient_phone' => ['nullable', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer'],
            'patient_gender' => ['nullable', 'string', 'max:255'],
            'patient_address' => ['nullable', 'string'],
            'patient_occupation' => ['nullable', 'string', 'max:255'],
        ];

        if ($partial) {
            // Preserve `nullable` instead of overwriting it — see the full
            // explanation in CompleteDentureRecordController::validateRecord().
            // Blindly replacing index 0 turned `['nullable', 'string']` into
            // `['sometimes', 'string']`; combined with Laravel's global
            // `ConvertEmptyStringsToNull` middleware (an empty string in the
            // body becomes `null` before validation), a correctly-sent empty
            // optional field failed with "must be a string" — reproduced via
            // a real HTTP PUT, not just a rule-level check.
            foreach ($rules as $field => $fieldRules) {
                if (($fieldRules[0] ?? null) === 'nullable') {
                    array_unshift($rules[$field], 'sometimes');
                } else {
                    $rules[$field][0] = 'sometimes';
                }
            }
        }

        return $request->validate($rules);
    }
}
