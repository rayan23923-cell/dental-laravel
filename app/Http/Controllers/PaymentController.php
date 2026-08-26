<?php

namespace App\Http\Controllers;

use App\Models\Appointment;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class PaymentController extends Controller
{
    public function index(Request $request): Response
    {
        $search = $request->string('search')->toString();

        $payments = Payment::with(['appointment', 'patientRegistration'])
            ->when($search !== '', fn ($q) => $q->where(fn ($q2) => $q2
                ->whereHas('appointment', fn ($q3) => $q3->where('full_name', 'like', "%{$search}%"))
                ->orWhereHas('patientRegistration', fn ($q3) => $q3->where('name', 'like', "%{$search}%"))))
            ->latest('paid_at')
            ->paginate(15)
            ->withQueryString();

        return Inertia::render('Payments/Index', [
            'payments' => $payments,
            'filters' => ['search' => $search],
        ]);
    }

    public function create(): Response
    {
        return Inertia::render('Payments/Create', [
            'appointments' => Appointment::orderByDesc('appointment_date')->get(['id', 'full_name', 'appointment_date']),
            // No longer loads every registration up front (2026-08-26) —
            // that full-table `<select>` didn't scale and was the exact
            // thing the user asked to replace with scan-or-search; see
            // `PatientRegistrationController::search()`.
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $this->validatePayment($request);

        if (! empty($validated['patient_registration_id'])) {
            try {
                PatientScreeningGate::ensureClear(PatientRegistration::findOrFail($validated['patient_registration_id']));
            } catch (PatientScreeningException $e) {
                return back()->with('error', $e->getMessage());
            }
        }

        Payment::create($validated);

        return redirect()->route('payments.index')->with('success', 'Payment recorded.');
    }

    public function destroy(Payment $payment): RedirectResponse
    {
        $payment->delete();

        return redirect()->route('payments.index')->with('success', 'Payment deleted.');
    }

    /**
     * A payment settles **either** an appointment **or** a reception-desk
     * registration — never both, never neither. Mirrors
     * `Api\PaymentController::validatePayment()`'s exact rule, which this
     * web form never adopted when `patient_registration_id` was added to
     * the schema (see the migration's docblock) — the API accepted it,
     * this form silently couldn't.
     */
    private function validatePayment(Request $request): array
    {
        return $request->validate([
            'appointment_id' => ['required_without:patient_registration_id', 'nullable', 'prohibits:patient_registration_id', 'exists:appointments,id'],
            'patient_registration_id' => ['required_without:appointment_id', 'nullable', 'exists:patients_simple,id'],
            'amount' => ['required', 'numeric', 'min:0'],
            'paid_by' => ['nullable', 'string', 'max:100'],
            'paid_at' => ['nullable', 'date'],
        ]);
    }
}
