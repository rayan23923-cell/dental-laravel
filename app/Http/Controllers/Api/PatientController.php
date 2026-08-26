<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PatientResource;
use App\Models\Patient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PatientController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $patients = Patient::with(['stage', 'doctor'])
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where('name', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%");
            })
            ->latest('created_at')
            ->paginate(15);

        return PatientResource::collection($patients)->response();
    }

    public function show(Patient $patient): JsonResponse
    {
        $patient->load(['stage', 'doctor']);

        return (new PatientResource($patient))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $patient = Patient::create($this->validatePatient($request));

        return (new PatientResource($patient))->response()->setStatusCode(201);
    }

    public function update(Request $request, Patient $patient): JsonResponse
    {
        $patient->update($this->validatePatient($request));

        return (new PatientResource($patient))->response();
    }

    public function destroy(Patient $patient): JsonResponse
    {
        $patient->delete();

        return response()->json(null, 204);
    }

    private function validatePatient(Request $request): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:20'],
            'stage_id' => ['nullable', 'exists:stages,id'],
            'doctor_id' => ['nullable', 'exists:doctors,id'],
        ]);
    }
}
