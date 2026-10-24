<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use App\Support\PaymentStats;
use Illuminate\Contracts\View\View;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use App\Services\PermissionManager;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class PaymentController extends Controller
{
    public function index(Request $request): Response
    {
        $query = $this->filteredQuery($request);
        $stats = new PaymentStats();

        return Inertia::render('Payments/Index', [
            'payments' => (clone $query)->latest('paid_at')->paginate(15)->withQueryString(),
            'filters' => $this->filters($request),
            // Income overview (2026-10-12, by request).
            'periods' => $stats->periods(),
            'daily' => $stats->daily(),
            'monthly' => $stats->monthly(),
            'filteredTotal' => (float) (clone $query)->sum('amount'),
            'bySource' => PaymentStats::bySource($query),
            'currency' => ClinicSetting::current()->clinic_currency,
            'can' => [
                'export' => ($permissions = new PermissionManager($request->user()))->can('payments', 'export'),
                'delete' => $permissions->can('payments', 'delete'),
            ],
        ]);
    }

    /**
     * Printable payments report (2026-10-12, by request): the income
     * overview, the charts and every payment matching the page's filters.
     * Printed from the browser, which also saves it as PDF.
     */
    public function report(Request $request): View
    {
        $query = $this->filteredQuery($request);
        $stats = new PaymentStats();

        return view('print.payments-report', [
            'settings' => ClinicSetting::current(),
            'filters' => $this->filters($request),
            'payments' => (clone $query)->with(['appointment', 'patientRegistration.service'])->latest('paid_at')->get(),
            'filteredTotal' => (float) (clone $query)->sum('amount'),
            'bySource' => PaymentStats::bySource($query),
            'periods' => $stats->periods(),
            'daily' => $stats->daily(),
            'monthly' => $stats->monthly(),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }

    /** The search / date range / source filters shared by `index()` and `report()`. */
    private function filteredQuery(Request $request)
    {
        $search = $request->string('search')->toString();
        $source = $request->string('source')->toString();

        return Payment::with(['appointment', 'patientRegistration'])
            ->when($search !== '', fn ($q) => $q->where(fn ($q2) => $q2
                ->whereHas('appointment', fn ($q3) => $q3->where('full_name', 'like', "%{$search}%"))
                ->orWhereHas('patientRegistration', fn ($q3) => $q3->where('name', 'like', "%{$search}%"))))
            // Filtering (2026-08-29) — see Api\PaymentController::index()'s
            // matching comment for why these two (date range + source) are
            // what's actually filterable on this table.
            ->when($request->date('from'), fn ($q, $from) => $q->whereDate('paid_at', '>=', $from))
            ->when($request->date('to'), fn ($q, $to) => $q->whereDate('paid_at', '<=', $to))
            ->when($source, fn ($q) => match ($source) {
                'appointment' => $q->whereNotNull('appointment_id'),
                'registration' => $q->whereNotNull('patient_registration_id')->where('type', '!=', Payment::TYPE_LAB),
                'lab' => $q->where('type', Payment::TYPE_LAB),
                default => $q,
            });
    }

    private function filters(Request $request): array
    {
        return [
            'search' => $request->string('search')->toString(),
            'from' => $request->string('from')->toString() ?: null,
            'to' => $request->string('to')->toString() ?: null,
            'source' => $request->string('source')->toString() ?: null,
        ];
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

    /**
     * Lab screening fee (2026-10-11) — JSON so `Payments/Create.vue` can
     * open the printable receipt right away. The amount is always the
     * clinic's configured `lab_fee`; not blocked by `PatientScreeningGate`
     * since the lab is paid before it screens. Paying twice is refused.
     */
    public function storeLab(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'patient_registration_id' => ['required', 'exists:patients_simple,id'],
            'paid_by' => ['nullable', 'string', 'max:100'],
        ]);

        $fee = ClinicSetting::current()->lab_fee;
        if ($fee === null) {
            return response()->json(['message' => 'لم تُحدَّد أجور المختبر في الإعدادات.'], 422);
        }

        $alreadyPaid = Payment::where('patient_registration_id', $validated['patient_registration_id'])
            ->where('type', Payment::TYPE_LAB)->exists();
        if ($alreadyPaid) {
            return response()->json(['message' => 'أجور المختبر مدفوعة مسبقًا لهذا المريض.'], 422);
        }

        $payment = Payment::create([
            'patient_registration_id' => $validated['patient_registration_id'],
            'amount' => $fee,
            'paid_by' => $validated['paid_by'] ?? null,
            'paid_at' => now(),
            'type' => Payment::TYPE_LAB,
        ]);

        return response()->json([
            'data' => [
                'id' => $payment->id,
                'receipt_url' => route('payments.receipt', ['payment' => $payment, 'autoprint' => 1]),
            ],
        ], 201);
    }

    /** Printable receipt — "تم دفع أجور المختبر" for lab-fee payments. */
    public function receipt(Request $request, Payment $payment): View
    {
        $payment->load('patientRegistration.service', 'patientRegistration.registerDay', 'appointment');

        return view('print.payment-receipt', [
            'settings' => ClinicSetting::current(),
            'payment' => $payment,
            'autoprint' => $request->boolean('autoprint'),
        ]);
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
