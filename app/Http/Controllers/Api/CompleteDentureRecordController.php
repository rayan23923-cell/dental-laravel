<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CompleteDentureRecordResource;
use App\Models\CompleteDentureRecord;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CompleteDentureRecordController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = CompleteDentureRecord::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return CompleteDentureRecordResource::collection($records)->response();
    }

    public function show(CompleteDentureRecord $record): JsonResponse
    {
        return (new CompleteDentureRecordResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = CompleteDentureRecord::create($this->validateRecord($request));

        return (new CompleteDentureRecordResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, CompleteDentureRecord $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new CompleteDentureRecordResource($record))->response();
    }

    public function destroy(CompleteDentureRecord $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'doctor_id' => ['required', 'integer'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_name' => ['nullable', 'string', 'max:255'],
            'age' => ['nullable', 'integer'],
            'sex' => ['nullable', 'string', 'max:255'],
            'telephone' => ['nullable', 'string', 'max:255'],
            'occupation' => ['nullable', 'string', 'max:255'],
            'address' => ['nullable', 'string'],
            'first_time' => ['nullable', 'string', 'max:255'],
            'medical_history' => ['nullable', 'string'],
            'dental_extraction_reason' => ['nullable', 'string'],
            'dentist_visit_regular' => ['nullable', 'string', 'max:255'],
            'last_tooth_extracted' => ['nullable', 'string', 'max:255'],
            'last_tooth_extracted_teeth' => ['nullable', 'string', 'max:255'],
            'complete_denture_reason' => ['nullable', 'string'],
            'partial_denture_reason' => ['nullable', 'string'],
            'previous_complete_denture' => ['nullable', 'string'],
            'previous_partial_denture' => ['nullable', 'string'],
            'not_using_reason' => ['nullable', 'string'],
            'new_denture_reason' => ['nullable', 'string'],
            'old_denture_retention' => ['nullable', 'string', 'max:255'],
            'old_denture_stability' => ['nullable', 'string', 'max:255'],
            'old_denture_centric' => ['nullable', 'string', 'max:255'],
            'old_denture_vertical' => ['nullable', 'string', 'max:255'],
            'old_denture_appearance' => ['nullable', 'string', 'max:255'],
            'old_denture_comfort' => ['nullable', 'string', 'max:255'],
            'facial_muscle_tone' => ['nullable', 'string', 'max:255'],
            'face_form' => ['nullable', 'string', 'max:255'],
            'angles_jaw_classification' => ['nullable', 'string', 'max:255'],
            'vertical_dimensions_rest' => ['nullable', 'string', 'max:255'],
            'ridge_form_upper' => ['nullable', 'string', 'max:255'],
            'ridge_form_lower' => ['nullable', 'string', 'max:255'],
            'mucosa_upper' => ['nullable', 'string', 'max:255'],
            'mucosa_lower' => ['nullable', 'string', 'max:255'],
            'palate_depth' => ['nullable', 'string', 'max:255'],
            'tongue_size' => ['nullable', 'string', 'max:255'],
            'bony_exostosis' => ['nullable', 'string', 'max:255'],
            'teeth_to_extract' => ['nullable', 'string', 'max:255'],
            'tmj_disorder' => ['nullable', 'string', 'max:255'],
            'muscles_mastication' => ['nullable', 'string', 'max:255'],
            'facial_tissue' => ['nullable', 'string', 'max:255'],
            'missing_teeth' => ['nullable', 'string', 'max:255'],
            'soft_tissue_condition' => ['nullable', 'string', 'max:255'],
            'abnormal_lesion' => ['nullable', 'string', 'max:255'],
            'abutments_mobility' => ['nullable', 'string', 'max:255'],
            'preprosthetic_treatment' => ['nullable', 'string'],
            'diagnosis_starting' => ['nullable', 'string'],
            'diagnosis_instructor_signature' => ['nullable', 'string'],
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
            'stage_cd_signature' => ['nullable', 'string'],
            'stage_cd_date' => ['nullable', 'date'],
            'stage_cd_grade' => ['nullable', 'string', 'max:255'],
            'stage_adjust1_signature' => ['nullable', 'string'],
            'stage_adjust1_date' => ['nullable', 'date'],
            'stage_adjust1_grade' => ['nullable', 'string', 'max:255'],
            'stage_finaleval_signature' => ['nullable', 'string'],
            'stage_finaleval_date' => ['nullable', 'date'],
            'stage_finaleval_grade' => ['nullable', 'string', 'max:255'],
        ];

        if ($partial) {
            // Real bug (found via a live Flutter PUT that failed validation
            // on a field it sent correctly): blindly overwriting index 0
            // turns `['nullable', 'string', ...]` into `['sometimes',
            // 'string', ...]`, silently dropping `nullable`. Laravel's
            // global `ConvertEmptyStringsToNull` middleware turns an empty
            // string in the request body into `null` before validation
            // ever runs — so a client that correctly sends `"field": ""`
            // for an optional column hits the `string` rule with a `null`
            // value and no `nullable` left to excuse it, failing with a
            // "must be a string" error for a request that did nothing
            // wrong. Only replace the first rule when it isn't `nullable`;
            // otherwise keep it and prepend `sometimes` instead, so both
            // "only validate if present" and "null/empty is fine" hold at
            // once — reproduced and confirmed fixed via a real HTTP PUT,
            // not just a unit-level rule check.
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
