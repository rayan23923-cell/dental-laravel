<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DentalChartResource;
use App\Models\DentalChart;
use App\Models\Doctor;
use App\Support\CaseSheetSignatures;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DentalChartController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $charts = DentalChart::with('doctor')
            ->when($doctor instanceof Doctor, fn ($q) => $q->where('doctor_id', $doctor->id))
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where('patient_id', 'like', "%{$search}%"))
            ->latest('visit_date')
            ->paginate(15);

        return DentalChartResource::collection($charts)->response();
    }

    public function show(DentalChart $dentalChart): JsonResponse
    {
        $dentalChart->load('doctor');

        return (new DentalChartResource($dentalChart))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $data = CaseSheetSignatures::applyPending('dental-charts', $this->validateChart($request), null, CaseSheetSignatures::signerName($request));
        $chart = DentalChart::create($data);

        return (new DentalChartResource($chart))->response()->setStatusCode(201);
    }

    public function update(Request $request, DentalChart $dentalChart): JsonResponse
    {
        $data = CaseSheetSignatures::applyPending('dental-charts', $this->validateChart($request, true), $dentalChart, CaseSheetSignatures::signerName($request));
        $dentalChart->update($data);

        return (new DentalChartResource($dentalChart))->response();
    }

    public function destroy(DentalChart $dentalChart): JsonResponse
    {
        $dentalChart->delete();

        return response()->json(null, 204);
    }

    private function validateChart(Request $request, bool $partial = false): array
    {
        return $request->validate([
            'patient_id' => [$partial ? 'sometimes' : 'required', 'string', 'max:255'],
            'patient_phone' => ['nullable', 'string', 'max:50'],
            'patient_age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'patient_sex' => ['nullable', 'string', 'max:20'],
            'patient_address' => ['nullable', 'string', 'max:255'],
            'patient_occupation' => ['nullable', 'string', 'max:255'],
            'doctor_id' => [$partial ? 'sometimes' : 'required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'exists:task_instances,id'],
            'task_id' => ['nullable', 'integer'],
            'chart_type' => [$partial ? 'sometimes' : 'required', 'in:primary,permanent'],
            'visit_date' => ['nullable', 'date'],
            'notes' => ['nullable', 'string'],
            'chief_complaint' => ['nullable', 'string'],
            'history_of_complaint' => ['nullable', 'string'],
            'oral_hygiene' => ['nullable', 'string'],
            'periodontal_condition' => ['nullable', 'string'],
            'non_vital_teeth' => ['nullable', 'string'],
            'missing_teeth' => ['nullable', 'string'],
            'crown_bridge_teeth' => ['nullable', 'string'],
            'tooth_data' => ['nullable', 'array'],
            'endodontics_data' => ['nullable', 'array'],
            'treatment_plan_date' => ['nullable', 'date'],
            'treatment_plan_notes' => ['nullable', 'string'],
            'senior_doctor_name' => ['nullable', 'string', 'max:255'],
            // Real bug found and fixed (2026-08-28, caught live via a curl
            // test of the supervisor-preview feature): missing here meant
            // `$request->validate()` silently dropped it from every save —
            // the web equivalent auto-generates its rules from
            // App\Support\OperativeForm::sections() (which does include
            // this field), so only this hand-written API rule set had the
            // gap. `senior_signature` is a real `$fillable` column and one
            // of `dental-charts`' own App\Support\CaseSheetSupervisorFields.
            'senior_signature' => ['nullable', 'string'],
        ]);
    }
}
