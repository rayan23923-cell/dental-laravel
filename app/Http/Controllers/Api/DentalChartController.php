<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DentalChartResource;
use App\Models\DentalChart;
use App\Models\Doctor;
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
        $chart = DentalChart::create($this->validateChart($request));

        return (new DentalChartResource($chart))->response()->setStatusCode(201);
    }

    public function update(Request $request, DentalChart $dentalChart): JsonResponse
    {
        $dentalChart->update($this->validateChart($request, true));

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
        ]);
    }
}
