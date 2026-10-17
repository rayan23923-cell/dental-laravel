<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PaymentResource;
use App\Models\ClinicSetting;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use App\Support\PaymentStats;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class PaymentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $payments = $this->filteredQuery($request)
            ->when($request->integer('appointment_id'), fn ($q, $id) => $q->where('appointment_id', $id))
            ->when(
                $request->integer('patient_registration_id'),
                fn ($q, $id) => $q->where('patient_registration_id', $id)
            )
            ->latest('paid_at')
            ->paginate(15);

        return PaymentResource::collection($payments)->response();
    }

    /**
     * The web payments page's income overview for the app (2026-10-17):
     * today / week / month / year, the daily and monthly charts, and the
     * total of the current filters by source. Same filters as `index()`.
     */
    public function stats(Request $request): JsonResponse
    {
        $query = $this->filteredQuery($request);
        $stats = new PaymentStats();

        return response()->json(['data' => [
            'periods' => $stats->periods(),
            'daily' => $stats->daily(),
            'monthly' => $stats->monthly(),
            'filtered_total' => (float) (clone $query)->sum('amount'),
            'by_source' => PaymentStats::bySource($query),
            'currency' => ClinicSetting::current()->clinic_currency,
        ]]);
    }

    /** Search, date range and source, shared by `index()` and `stats()`. */
    private function filteredQuery(Request $request)
    {
        $search = $request->string('search')->toString();

        return Payment::with(['appointment', 'patientRegistration'])
            // Mirrors PaymentController (web)'s own search — a person's
            // payment history should be findable the same way regardless
            // of which client is asking.
            ->when($search !== '', fn ($q) => $q->where(fn ($q2) => $q2
                ->whereHas('appointment', fn ($q3) => $q3->where('full_name', 'like', "%{$search}%"))
                ->orWhereHas('patientRegistration', fn ($q3) => $q3->where('name', 'like', "%{$search}%"))))
            // Filtering (2026-08-29) — a date range on `paid_at` (the only
            // date this table has) and which of the two mutually-exclusive
            // sources a payment settled (see `validatePayment()`'s
            // required_without/prohibits pair — there's no direct doctor
            // link on `payments` to filter by, and no separate paid/unpaid
            // flag either; a `Payment` row already **is** a paid
            // transaction).
            ->when($request->date('from'), fn ($q, $from) => $q->whereDate('paid_at', '>=', $from))
            ->when($request->date('to'), fn ($q, $to) => $q->whereDate('paid_at', '<=', $to))
            ->when($request->string('source')->toString(), fn ($q, $source) => match ($source) {
                'appointment' => $q->whereNotNull('appointment_id'),
                'registration' => $q->whereNotNull('patient_registration_id')->where('type', '!=', Payment::TYPE_LAB),
                'lab' => $q->where('type', Payment::TYPE_LAB),
                default => $q,
            });
    }

    public function show(Payment $payment): JsonResponse
    {
        $payment->load(['appointment', 'patientRegistration']);

        return (new PaymentResource($payment))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validatePayment($request);

        // The lab fee is paid *before* screening, so it skips the gate.
        if (! empty($validated['patient_registration_id']) && ($validated['type'] ?? Payment::TYPE_SERVICE) !== Payment::TYPE_LAB) {
            try {
                PatientScreeningGate::ensureClear(PatientRegistration::findOrFail($validated['patient_registration_id']));
            } catch (PatientScreeningException $e) {
                return response()->json(['message' => $e->getMessage()], 422);
            }
        }

        // Lab fee: always the configured amount, once per registration.
        if (($validated['type'] ?? null) === Payment::TYPE_LAB) {
            $fee = ClinicSetting::current()->lab_fee;
            if ($fee === null || empty($validated['patient_registration_id'])) {
                return response()->json(['message' => 'لم تُحدَّد أجور المختبر في الإعدادات.'], 422);
            }
            if (Payment::where('patient_registration_id', $validated['patient_registration_id'])->where('type', Payment::TYPE_LAB)->exists()) {
                return response()->json(['message' => 'أجور المختبر مدفوعة مسبقًا لهذا المريض.'], 422);
            }
            $validated['amount'] = $fee;
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
            'type' => ['sometimes', Rule::in([Payment::TYPE_SERVICE, Payment::TYPE_LAB])],
        ]);
    }
}
