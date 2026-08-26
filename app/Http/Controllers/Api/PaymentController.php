<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PaymentResource;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PaymentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $search = $request->string('search')->toString();

        $payments = Payment::with(['appointment', 'patientRegistration'])
            ->when($request->integer('appointment_id'), fn ($q, $id) => $q->where('appointment_id', $id))
            ->when(
                $request->integer('patient_registration_id'),
                fn ($q, $id) => $q->where('patient_registration_id', $id)
            )
            // Mirrors PaymentController (web)'s own search — a person's
            // payment history should be findable the same way regardless
            // of which client is asking.
            ->when($search !== '', fn ($q) => $q->where(fn ($q2) => $q2
                ->whereHas('appointment', fn ($q3) => $q3->where('full_name', 'like', "%{$search}%"))
                ->orWhereHas('patientRegistration', fn ($q3) => $q3->where('name', 'like', "%{$search}%"))))
            ->latest('paid_at')
            ->paginate(15);

        return PaymentResource::collection($payments)->response();
    }

    public function show(Payment $payment): JsonResponse
    {
        $payment->load(['appointment', 'patientRegistration']);

        return (new PaymentResource($payment))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validatePayment($request);

        if (! empty($validated['patient_registration_id'])) {
            try {
                PatientScreeningGate::ensureClear(PatientRegistration::findOrFail($validated['patient_registration_id']));
            } catch (PatientScreeningException $e) {
                return response()->json(['message' => $e->getMessage()], 422);
            }
        }

        $payment = Payment::create($validated);

        return (new PaymentResource($payment))->response()->setStatusCode(201);
    }

    public function update(Request $request, Payment $payment): JsonResponse
    {
        $payment->update($this->validatePayment($request, true));

        return (new PaymentResource($payment))->response();
    }

    public function destroy(Payment $payment): JsonResponse
    {
        $payment->delete();

        return response()->json(null, 204);
    }

    /**
     * A payment settles **either** an appointment (the original flow)
     * **or** a reception-desk registration (the ticket-QR desk flow) —
     * never both, never neither. `required_without`/`prohibits` express
     * that pair-wise; the database can't (see the migration that added
     * `patient_registration_id`).
     */
    private function validatePayment(Request $request, bool $partial = false): array
    {
        $presence = $partial ? ['sometimes'] : ['required_without:patient_registration_id'];

        return $request->validate([
            'appointment_id' => [...$presence, 'nullable', 'prohibits:patient_registration_id', 'exists:appointments,id'],
            'patient_registration_id' => [
                $partial ? 'sometimes' : 'required_without:appointment_id',
                'nullable',
                'exists:patients_simple,id',
            ],
            'amount' => [$partial ? 'sometimes' : 'required', 'numeric', 'min:0'],
            'paid_by' => ['nullable', 'string', 'max:100'],
            'paid_at' => ['nullable', 'date'],
        ]);
    }
}
