<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\OralMedicineChartResource;
use App\Models\OralMedicineChart;
use App\Support\CaseSheetSignatures;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class OralMedicineChartController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = OralMedicineChart::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return OralMedicineChartResource::collection($records)->response();
    }

    public function show(OralMedicineChart $record): JsonResponse
    {
        return (new OralMedicineChartResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $data = CaseSheetSignatures::applyPending('oral-medicine-charts', $this->validateRecord($request), null, CaseSheetSignatures::signerName($request));
        $record = OralMedicineChart::create($data);

        return (new OralMedicineChartResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, OralMedicineChart $record): JsonResponse
    {
        $data = CaseSheetSignatures::applyPending('oral-medicine-charts', $this->validateRecord($request, true), $record, CaseSheetSignatures::signerName($request));
        $record->update($data);

        return (new OralMedicineChartResource($record))->response();
    }

    public function destroy(OralMedicineChart $record): JsonResponse
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
            'case_no' => ['nullable', 'string', 'max:255'],
            'visit_date' => ['nullable', 'date'],
            'patient_id' => ['nullable', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer'],
            'patient_sex' => ['nullable', 'string', 'max:255'],
            'patient_address' => ['nullable', 'string'],
            'patient_occupation' => ['nullable', 'string', 'max:255'],
            'patient_phone' => ['nullable', 'string', 'max:255'],
            'chief_complaint' => ['nullable', 'string'],
            'past_medical_history' => ['nullable', 'string'],
            'surgical_history' => ['nullable', 'string'],
            'family_history' => ['nullable', 'string'],
            'social_history' => ['nullable', 'string'],
            'clinical_examination' => ['nullable', 'string'],
            'extraoral_intraoral_examination' => ['nullable', 'string'],
            'present_teeth' => ['nullable', 'string'],
            'teeth_requiring_treatment' => ['nullable', 'string'],
            'jaws_teeth_relations' => ['nullable', 'string'],
            'history_of_complaint' => ['nullable', 'string'],
            'investigations_diagnosis' => ['nullable', 'string'],
            'student_visits' => ['nullable', 'string'],
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
