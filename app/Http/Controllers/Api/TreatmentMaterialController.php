<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\TreatmentMaterialResource;
use App\Models\TreatmentMaterial;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TreatmentMaterialController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $records = TreatmentMaterial::query()
            ->when($request->integer('tooth_treatment_id'), fn ($q, $id) => $q->where('tooth_treatment_id', $id))
            ->latest('id')
            ->paginate(15);

        return TreatmentMaterialResource::collection($records)->response();
    }

    public function show(TreatmentMaterial $record): JsonResponse
    {
        return (new TreatmentMaterialResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $record = TreatmentMaterial::create($this->validateRecord($request));

        return (new TreatmentMaterialResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, TreatmentMaterial $record): JsonResponse
    {
        $record->update($this->validateRecord($request, true));

        return (new TreatmentMaterialResource($record))->response();
    }

    public function destroy(TreatmentMaterial $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'tooth_treatment_id' => ['required', 'integer'],
            'material_name' => ['required', 'string', 'max:255'],
            'material_type' => ['required', 'string', 'max:255'],
            'quantity' => ['nullable', 'string', 'max:255'],
            'unit' => ['nullable', 'string', 'max:255'],
            'cost' => ['nullable', 'string', 'max:255'],
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
