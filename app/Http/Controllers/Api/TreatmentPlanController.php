<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\TreatmentPlanResource;
use App\Models\TreatmentPlan;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TreatmentPlanController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $records = TreatmentPlan::query()
            ->when($request->integer('chart_id'), fn ($q, $id) => $q->where('chart_id', $id))
            ->latest('id')
            ->paginate(15);

        return TreatmentPlanResource::collection($records)->response();
    }

    public function show(TreatmentPlan $record): JsonResponse
    {
        return (new TreatmentPlanResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = TreatmentPlan::create($this->validateRecord($request));

        return (new TreatmentPlanResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, TreatmentPlan $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new TreatmentPlanResource($record))->response();
    }

    public function destroy(TreatmentPlan $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'chart_id' => ['required', 'integer'],
            'plan_date' => ['nullable', 'date'],
            'plan_notes' => ['nullable', 'string'],
            'mark' => ['nullable', 'string', 'max:255'],
            'doctor_name' => ['nullable', 'string', 'max:255'],
            'signature' => ['nullable', 'string'],
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
