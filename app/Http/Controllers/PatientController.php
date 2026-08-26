<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\Patient;
use App\Models\Stage;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class PatientController extends Controller
{
    public function index(Request $request): Response
    {
        $patients = Patient::with(['stage', 'doctor'])
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where('name', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%");
            })
            ->latest('created_at')
            ->paginate(15)
            ->withQueryString();

        return Inertia::render('Patients/Index', [
            'patients' => $patients,
            'filters' => $request->only('search'),
        ]);
    }

    public function create(): Response
    {
        return Inertia::render('Patients/Create', [
            'stages' => Stage::orderBy('name')->get(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        Patient::create($this->validatePatient($request));

        return redirect()->route('patients.index')->with('success', 'Patient registered successfully.');
    }

    public function edit(Patient $patient): Response
    {
        return Inertia::render('Patients/Edit', [
            'patient' => $patient,
            'stages' => Stage::orderBy('name')->get(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
        ]);
    }

    public function update(Request $request, Patient $patient): RedirectResponse
    {
        $patient->update($this->validatePatient($request));

        return redirect()->route('patients.index')->with('success', 'Patient updated successfully.');
    }

    public function destroy(Patient $patient): RedirectResponse
    {
        $patient->delete();

        return redirect()->route('patients.index')->with('success', 'Patient deleted successfully.');
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
