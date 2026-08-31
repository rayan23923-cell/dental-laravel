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
            'chart_date' => ['required', 'date'],
            'exam_type' => ['nullable', 'string', 'max:50'],
            'notes' => ['nullable', 'string'],
            'senior_signature' => ['nullable', 'string'],
            'chart_data' => ['required', 'string'],
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
