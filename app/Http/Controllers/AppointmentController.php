<?php

namespace App\Http\Controllers;

use App\Models\Appointment;
use App\Models\PatientRegistration;
use App\Models\Task;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class AppointmentController extends Controller
{
    public function index(Request $request): Response
    {
        $appointments = Appointment::with(['patient', 'patientRegistration', 'doctor', 'task', 'payments'])
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where('full_name', 'like', "%{$search}%"))
            ->orderByDesc('appointment_date')
            ->paginate(15)
            ->withQueryString();

        return Inertia::render('Appointments/Index', [
            'appointments' => $appointments,
            'filters' => $request->only('search'),
        ]);
    }

    public function create(): Response
    {
        return Inertia::render('Appointments/Form', [
            'appointment' => null,
            ...$this->formOptions(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        Appointment::create($this->validateAppointment($request));

        return redirect()->route('appointments.index')->with('success', 'Appointment created.');
    }

    public function edit(Appointment $appointment): Response
    {
        return Inertia::render('Appointments/Form', [
            'appointment' => $appointment,
            ...$this->formOptions(),
        ]);
    }

    public function update(Request $request, Appointment $appointment): RedirectResponse
    {
        $appointment->update($this->validateAppointment($request, partial: true));

        return redirect()->route('appointments.index')->with('success', 'Appointment updated.');
    }

    public function destroy(Appointment $appointment): RedirectResponse
    {
        $appointment->delete();

        return redirect()->route('appointments.index')->with('success', 'Appointment deleted.');
    }

    public function togglePinned(Appointment $appointment): RedirectResponse
    {
        $appointment->update(['pinned' => ! $appointment->pinned]);

        return back()->with('success', $appointment->pinned ? 'Appointment pinned.' : 'Appointment unpinned.');
    }

    private function formOptions(): array
    {
        return [
            // Replaces the plain `patients` list — new appointments are
            // created via a registered patient ("المرضى المسجلين") only,
            // not the plain patients table (see the migration that added
            // patient_registration_id).
            'patientRegistrations' => PatientRegistration::orderBy('name')->get(['id', 'name', 'phone']),
            // appointments.doctor_id references users.id (staff), not doctors.id —
            // see App\Models\Appointment for the confirmed FK constraint.
            'doctorUsers' => User::orderBy('full_name')->get(['id', 'full_name', 'role']),
            'tasks' => Task::orderBy('title')->get(['id', 'title']),
        ];
    }

    /**
     * `$partial` (used by `update()` only) makes `patient_registration_id`
     * optional — an existing appointment created before this column
     * existed has no registration to submit, and editing it (say, just
     * its date) shouldn't be blocked on picking one retroactively. New
     * appointments (`store()`) always require it.
     */
    private function validateAppointment(Request $request, bool $partial = false): array
    {
        // A blank select submits '' , not null/absent — same bug class as
        // Doctor's nfc_tag_id field (see that controller's fix): without
        // this, editing an old appointment (no patient_registration_id to
        // pre-fill, field left blank) would fail `exists:patients_simple,id`
        // against an empty string instead of being skipped by `sometimes`.
        if ($request->input('patient_registration_id') === '') {
            $request->merge(['patient_registration_id' => null]);
        }

        return $request->validate([
            'full_name' => ['required', 'string', 'max:250'],
            'patient_registration_id' => [$partial ? 'sometimes' : 'required', 'nullable', 'exists:patients_simple,id'],
            'doctor_id' => ['required', 'exists:users,id'],
            'task_id' => ['required', 'exists:tasks,id'],
            'appointment_date' => ['required', 'date'],
            'confirmed_by_accountant' => ['boolean'],
            'pinned' => ['boolean'],
        ]);
    }
}
