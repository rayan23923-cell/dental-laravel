<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\AdvancedPeriodontalChartResource;
use App\Models\AdvancedPeriodontalChart;
use App\Models\Patient;
use App\Support\CaseSheetSignatures;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdvancedPeriodontalChartController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = AdvancedPeriodontalChart::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return AdvancedPeriodontalChartResource::collection($records)->response();
    }

    public function show(AdvancedPeriodontalChart $record): JsonResponse
    {
        return (new AdvancedPeriodontalChartResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validateRecord($request);
        $data = CaseSheetSignatures::applyPending('advanced-periodontal-charts', $data, null, CaseSheetSignatures::signerName($request));
        $data['patient_id'] = $this->resolvePatientId($data);

        $record = AdvancedPeriodontalChart::create($data);

        return (new AdvancedPeriodontalChartResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, AdvancedPeriodontalChart $record): JsonResponse
    {
        $data = $this->validateRecord($request, true);
        $data = CaseSheetSignatures::applyPending('advanced-periodontal-charts', $data, $record, CaseSheetSignatures::signerName($request));
        $data['patient_id'] = $this->resolvePatientId($data, $record->patient_id);

        $record->update($data);

        return (new AdvancedPeriodontalChartResource($record))->response();
    }

    public function destroy(AdvancedPeriodontalChart $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    /** Same resolvePatientId pattern every case-sheet API controller uses. */
    private function resolvePatientId(array $data, ?int $currentId = null): ?int
    {
        $name = trim(($data['patient_first_name'] ?? '').' '.($data['patient_last_name'] ?? ''));
        if ($name === '') {
            return $currentId;
        }

        return (Patient::where('name', $name)->first() ?? Patient::create(['name' => $name]))->id;
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_id' => ['nullable', 'integer'],
            'doctor_id' => ['required', 'integer'],
            'patient_last_name' => ['nullable', 'string', 'max:255'],
            'patient_first_name' => ['nullable', 'string', 'max:255'],
            'patient_dob' => ['nullable', 'date'],
            'patient_gender' => ['nullable', 'string', 'max:10'],
            'chart_date' => ['required', 'date'],
            'exam_type' => ['nullable', 'string', 'max:50'],
            'notes' => ['nullable', 'string'],
            'senior_signature' => ['nullable', 'string'],
            'chart_data' => ['required', 'string'],
            // Merged in from PeriodontalChartForm (2026-09-03, by request) —
            // rule shapes copied from this same file's regular
            // Api\PeriodontalChartController counterpart. See
            // AdvancedPeriodontalChartForm's doc comment for what's
            // deliberately NOT merged (Patient Information, chartGroups()'s
            // table, any tooth/odontogram field).
            'women_pregnancy' => ['nullable', 'string', 'max:255'],
            'pregnancy_weeks' => ['nullable', 'string', 'max:50'],
            'women_birth_control' => ['nullable', 'string', 'max:255'],
            'women_nursing' => ['nullable', 'string', 'max:255'],
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
            'exam_bpe_ur' => ['nullable', 'string', 'max:10'],
            'exam_bpe_ua' => ['nullable', 'string', 'max:10'],
            'exam_bpe_ul' => ['nullable', 'string', 'max:10'],
            'exam_bpe_lr' => ['nullable', 'string', 'max:10'],
            'exam_bpe_la' => ['nullable', 'string', 'max:10'],
            'exam_bpe_ll' => ['nullable', 'string', 'max:10'],
            'exam_radiograph_periapical' => ['nullable', 'boolean'],
            'exam_radiograph_bitewing' => ['nullable', 'boolean'],
            'exam_radiograph_panoramic' => ['nullable', 'boolean'],
            'exam_radiograph_cbct' => ['nullable', 'boolean'],
            'exam_other_investigations' => ['nullable', 'string'],
            'oral_hygiene' => ['nullable', 'string'],
            'periodontal_condition' => ['nullable', 'string'],
            'diagnosis_pattern' => ['nullable', 'string', 'max:255'],
            'diagnosis_stage' => ['nullable', 'string', 'max:50'],
            'diagnosis_grade' => ['nullable', 'string', 'max:50'],
            'diagnosis_status' => ['nullable', 'string', 'max:50'],
            'diagnosis_risk_factors' => ['nullable', 'string'],
            'treatment_plan' => ['nullable', 'string'],
            'treatment_plan_date' => ['nullable', 'date'],
            'senior_doctor_name' => ['nullable', 'string', 'max:255'],
            'approval_date' => ['nullable', 'date'],
            'clinical_notes' => ['nullable', 'string'],
        ];

        if ($partial) {
            // Same reasoning as every other case-sheet API controller's
            // partial-update branch — see PeriodontalChartController's own
            // copy for the full explanation.
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
