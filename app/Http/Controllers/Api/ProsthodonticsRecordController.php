<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProsthodonticsRecordResource;
use App\Models\ProsthodonticsRecord;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProsthodonticsRecordController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = ProsthodonticsRecord::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return ProsthodonticsRecordResource::collection($records)->response();
    }

    public function show(ProsthodonticsRecord $record): JsonResponse
    {
        return (new ProsthodonticsRecordResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = ProsthodonticsRecord::create($this->validateRecord($request));

        return (new ProsthodonticsRecordResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, ProsthodonticsRecord $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new ProsthodonticsRecordResource($record))->response();
    }

    public function destroy(ProsthodonticsRecord $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'task_instances_id' => ['nullable', 'integer'],
            'doctor_id' => ['required', 'integer'],
            'student_name' => ['nullable', 'string', 'max:255'],
            'patient_name' => ['nullable', 'string', 'max:255'],
            'patient_phone' => ['nullable', 'string', 'max:255'],
            'group_name' => ['nullable', 'string', 'max:255'],
            'age' => ['nullable', 'integer'],
            'sex' => ['nullable', 'string', 'max:255'],
            'telephone' => ['nullable', 'string', 'max:255'],
            'occupation' => ['nullable', 'string', 'max:255'],
            'address' => ['nullable', 'string'],
            'first_time' => ['nullable', 'string', 'max:255'],
            'medical_history' => ['nullable', 'string'],
            'dental_extraction_reason' => ['nullable', 'string'],
            'dentist_visit_regular' => ['nullable', 'string'],
            'partial_denture_reason' => ['nullable', 'string'],
            'previous_partial_denture' => ['nullable', 'string'],
            'not_using_reason' => ['nullable', 'string'],
            'tmj_disorder' => ['nullable', 'string', 'max:255'],
            'muscles_mastication' => ['nullable', 'string', 'max:255'],
            'facial_tissue' => ['nullable', 'string', 'max:255'],
            'missing_teeth' => ['nullable', 'string'],
            'caries_teeth' => ['nullable', 'string'],
            'soft_tissue_condition' => ['nullable', 'string'],
            'abnormal_lesion' => ['nullable', 'string'],
            'abutments_mobility' => ['nullable', 'string'],
            'teeth_extraction' => ['nullable', 'string'],
            'preprosthetic_treatment' => ['nullable', 'string'],
            'diagnosis_starting' => ['nullable', 'string'],
            'diagnosis_instructor_signature' => ['nullable', 'string'],
            'diagnosis_date' => ['nullable', 'date'],
            'diagnosis_grade' => ['nullable', 'string', 'max:255'],
            'stage_preliminary_signature' => ['nullable', 'string'],
            'stage_preliminary_date' => ['nullable', 'date'],
            'stage_preliminary_grade' => ['nullable', 'string', 'max:255'],
            'stage_surveying_signature' => ['nullable', 'string'],
            'stage_surveying_date' => ['nullable', 'date'],
            'stage_surveying_grade' => ['nullable', 'string', 'max:255'],
            'stage_final_signature' => ['nullable', 'string'],
            'stage_final_date' => ['nullable', 'date'],
            'stage_final_grade' => ['nullable', 'string', 'max:255'],
            'stage_jawrel_signature' => ['nullable', 'string'],
            'stage_jawrel_date' => ['nullable', 'date'],
            'stage_jawrel_grade' => ['nullable', 'string', 'max:255'],
            'stage_trial_signature' => ['nullable', 'string'],
            'stage_trial_date' => ['nullable', 'date'],
            'stage_trial_grade' => ['nullable', 'string', 'max:255'],
            'stage_flasking_signature' => ['nullable', 'string'],
            'stage_flasking_date' => ['nullable', 'date'],
            'stage_flasking_grade' => ['nullable', 'string', 'max:255'],
            'stage_rpd_signature' => ['nullable', 'string'],
            'stage_rpd_date' => ['nullable', 'date'],
            'stage_rpd_grade' => ['nullable', 'string', 'max:255'],
            'stage_adjust1_signature' => ['nullable', 'string'],
            'stage_adjust1_date' => ['nullable', 'date'],
            'stage_adjust1_grade' => ['nullable', 'string', 'max:255'],
            'stage_finaleval_signature' => ['nullable', 'string'],
            'stage_finaleval_date' => ['nullable', 'date'],
            'stage_finaleval_grade' => ['nullable', 'string', 'max:255'],
            'tooth_chart_data' => ['nullable', 'string'],
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
