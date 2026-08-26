<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\SurgeryFollowUpResource;
use App\Models\SurgeryFollowUp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SurgeryFollowUpController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $records = SurgeryFollowUp::query()
            ->when($request->integer('surgery_id'), fn ($q, $id) => $q->where('surgery_id', $id))
            ->latest('id')
            ->paginate(15);

        return SurgeryFollowUpResource::collection($records)->response();
    }

    public function show(SurgeryFollowUp $record): JsonResponse
    {
        return (new SurgeryFollowUpResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = SurgeryFollowUp::create($this->validateRecord($request));

        return (new SurgeryFollowUpResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, SurgeryFollowUp $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new SurgeryFollowUpResource($record))->response();
    }

    public function destroy(SurgeryFollowUp $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'surgery_id' => ['required', 'integer'],
            'follow_up_date' => ['required', 'date'],
            'findings' => ['nullable', 'string'],
            'patient_status' => ['nullable', 'string', 'max:255'],
            'next_appointment' => ['nullable', 'date'],
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
