<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\OrthodonticsRecordResource;
use App\Models\OrthodonticsRecord;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class OrthodonticsRecordController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = OrthodonticsRecord::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return OrthodonticsRecordResource::collection($records)->response();
    }

    public function show(OrthodonticsRecord $record): JsonResponse
    {
        return (new OrthodonticsRecordResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = OrthodonticsRecord::create($this->validateRecord($request));

        return (new OrthodonticsRecordResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, OrthodonticsRecord $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new OrthodonticsRecordResource($record))->response();
    }

    public function destroy(OrthodonticsRecord $record): JsonResponse
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
            'student_name' => ['nullable', 'string', 'max:255'],
            'group_name' => ['nullable', 'string', 'max:255'],
            'supervised_by' => ['nullable', 'string', 'max:255'],
            'patient_name' => ['required', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer'],
            'patient_sex' => ['nullable', 'string', 'max:255'],
            'patient_address' => ['nullable', 'string'],
            'patient_phone' => ['nullable', 'string', 'max:255'],
            'referral_date' => ['nullable', 'date'],
            'referred_from' => ['nullable', 'string', 'max:255'],
            'examination_data' => ['nullable', 'string'],
            'supervisor_notes' => ['nullable', 'string'],
            'supervisor_signature' => ['nullable', 'string'],
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
