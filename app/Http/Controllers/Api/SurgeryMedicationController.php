<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\SurgeryMedicationResource;
use App\Models\SurgeryMedication;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SurgeryMedicationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $records = SurgeryMedication::query()
            ->when($request->integer('surgery_id'), fn ($q, $id) => $q->where('surgery_id', $id))
            ->latest('id')
            ->paginate(15);

        return SurgeryMedicationResource::collection($records)->response();
    }

    public function show(SurgeryMedication $record): JsonResponse
    {
        return (new SurgeryMedicationResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = SurgeryMedication::create($this->validateRecord($request));

        return (new SurgeryMedicationResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, SurgeryMedication $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new SurgeryMedicationResource($record))->response();
    }

    public function destroy(SurgeryMedication $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'surgery_id' => ['required', 'integer'],
            'medication_name' => ['required', 'string', 'max:255'],
            'dosage' => ['nullable', 'string', 'max:255'],
            'frequency' => ['nullable', 'string', 'max:255'],
            'duration' => ['nullable', 'string', 'max:255'],
            'notes' => ['nullable', 'string'],
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
