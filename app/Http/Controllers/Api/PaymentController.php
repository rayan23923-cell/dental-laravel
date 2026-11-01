<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PaymentResource;
use App\Models\ClinicSetting;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use App\Support\PaymentScope;
use App\Support\PaymentStats;
use App\Support\StudentDiscount;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class PaymentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $payments = $this->filteredQuery($request, PaymentScope::sources($request->user()))
            ->latest('paid_at')
            ->paginate(15);

        return PaymentResource::collection($payments)->response();
    }

    /**
     * Income overview for the app's payments screen (2026-10-17), the same
     * figures the web `Payments/Index` page shows (see `PaymentStats`):
     * the four periods and the two chart series ignore the filters, the
     * total and per-source split follow them. Amounts are in the clinic's
     * currency, which is sent along so the app can label them.
     */
    public function stats(Request $request): JsonResponse
    {
        $sources = PaymentScope::sources($request->user());
        $query = $this->filteredQuery($request, $sources);
        $stats = new PaymentStats(null, $sources);

        return response()->json([
            'data' => [
                'periods' => $stats->periods(),
                'daily' => $stats->daily(),
                'monthly' => $stats->monthly(),
                'filtered_total' => (float) (clone $query)->sum('amount'),
                'by_source' => PaymentStats::bySource($query, $sources),
                'scope' => $sources,
                'currency' => ClinicSetting::current()->clinic_currency,
            ],
        ]);
    }

    /**
     * The payments report for the app's PDF (2026-10-17), the data of the
     * web `print/payments-report` page: the same overview as `stats()`
     * plus every payment matching the list's filters (not paginated), with
     * each registration's service.
     */
    public function report(Request $request): JsonResponse
    {
        $sources = PaymentScope::sources($request->user(), true);
        $query = $this->filteredQuery($request, $sources);
        $stats = new PaymentStats(null, $sources);

        $payments = (clone $query)->with(['appointment', 'patientRegistration.service'])->latest('paid_at')->get();
        $source = $request->string('source')->toString() ?: null;

        return response()->json([
            'data' => [
                'payments' => PaymentResource::collection($payments)->resolve(),
                // The report's last page (2026-11-01, by request): care-code
                // patients and the student/employee discount's beneficiaries.
                'supported' => \App\Support\SupportCodes::reportRowsFor([
                    'from' => $request->string('from')->toString() ?: null,
                    'to' => $request->string('to')->toString() ?: null,
                    'search' => $request->string('search')->toString(),
                    'source' => $source,
                ], $sources),
                'discounted' => \App\Support\SupportCodes::discountRows($payments),
                'periods' => $stats->periods(),
                'daily' => $stats->daily(),
                'monthly' => $stats->monthly(),
                'filtered_total' => (float) (clone $query)->sum('amount'),
                'by_source' => PaymentStats::bySource($query, $sources),
                'scope' => $sources,
                'currency' => ClinicSetting::current()->clinic_currency,
            ],
        ]);
    }

    /**
     * The search / date range / source filters shared by `index()` and
     * `stats()`/`report()`, within the account's [$sources]: the lab fees
     * or the tickets' income only for the lab / ticket-desk grants
     * (2026-10-26, by request, see PaymentScope).
     */
    private function filteredQuery(Request $request, ?array $sources): Builder
    {
        $search = $request->string('search')->toString();

        return PaymentScope::apply(Payment::with(['appointment', 'patientRegistration']), $sources)
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

    public function show(Request $request, Payment $payment): JsonResponse
    {
        abort_unless(PaymentScope::allows(PaymentScope::sources($request->user()), $payment), 403);
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

        // Free with a care code (2026-11-01): nothing is charged to that patient.
        if (! empty($validated['patient_registration_id'])
            && PatientRegistration::whereKey($validated['patient_registration_id'])->whereNotNull('support_code_id')->exists()) {
            return response()->json(['message' => 'هذا المريض '.\App\Support\SupportCodes::LABEL.'، فلا أجور عليه.'], 422);
        }

        // Lab fee: always the configured amount, once per registration.
        if (($validated['type'] ?? null) === Payment::TYPE_LAB) {
            // Less the student discount when the patient is eligible (2026-10-25).
            $fee = empty($validated['patient_registration_id'])
                ? null
                : StudentDiscount::labFee(PatientRegistration::find($validated['patient_registration_id']));
            if ($fee === null) {
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

    // No `update()` (2026-10-17): payments are no longer edited by hand —
    // the web dropped its add/edit page (2026-10-14) and the amounts are
    // fixed (the service's price at registration, the lab fee with the
    // result), so `PUT /payments/{id}` is not routed any more.

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
    private function validatePayment(Request $request): array
    {
        return $request->validate([
            'appointment_id' => ['required_without:patient_registration_id', 'nullable', 'prohibits:patient_registration_id', 'exists:appointments,id'],
            'patient_registration_id' => ['required_without:appointment_id', 'nullable', 'exists:patients_simple,id'],
            'amount' => ['required', 'numeric', 'min:0'],
            'paid_by' => ['nullable', 'string', 'max:100'],
            'paid_at' => ['nullable', 'date'],
            'type' => ['sometimes', Rule::in([Payment::TYPE_SERVICE, Payment::TYPE_LAB])],
        ]);
    }
}
