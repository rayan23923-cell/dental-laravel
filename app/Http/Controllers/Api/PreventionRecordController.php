<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PreventionRecordResource;
use App\Models\PreventionRecord;
use App\Support\CaseSheetSignatures;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PreventionRecordController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = PreventionRecord::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return PreventionRecordResource::collection($records)->response();
    }

    public function show(PreventionRecord $record): JsonResponse
    {
        return (new PreventionRecordResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_data'] = $this->withDefaultDate($data['patient_data'] ?? null);
        $data = CaseSheetSignatures::applyPending('prevention-records', $data, null, CaseSheetSignatures::signerName($request));

        $record = PreventionRecord::create($data);

        return (new PreventionRecordResource($record))->response()->setStatusCode(201);
    }

    /**
     * Mirrors `App\Http\Controllers\PreventionRecordController::prepare()`'s
     * matching comment — `patient_data.date` no longer has its own form
     * field, set automatically instead, once, at creation only.
     */
    private function withDefaultDate(?string $patientData): string
    {
        $decoded = json_decode($patientData ?? '{}', true) ?: [];
        $decoded['date'] = now()->toDateString();

        return json_encode($decoded);
    }

    public function update(Request $request, PreventionRecord $record): JsonResponse
    {
        $data = CaseSheetSignatures::applyPending('prevention-records', $this->validateRecord($request, true), $record, CaseSheetSignatures::signerName($request));
        $record->update($data);

        return (new PreventionRecordResource($record))->response();
    }

    public function destroy(PreventionRecord $record): JsonResponse
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
            'patient_data' => ['nullable', 'string'],
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
