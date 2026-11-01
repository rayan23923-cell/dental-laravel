<?php

namespace App\Http\Controllers;

use App\Models\ActivityLog;
use App\Models\ClinicSetting;
use App\Models\Payment;
use App\Models\PatientRegistration;
use App\Services\PatientScreeningException;
use App\Services\PatientScreeningGate;
use App\Support\PaymentScope;
use App\Support\PaymentStats;
use App\Support\StudentDiscount;
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
        // Lab fees only / ticket income only for the lab and ticket-desk
        // grants (2026-10-26, by request); null is every payment.
        $sources = PaymentScope::sources($request->user());
        $query = $this->filteredQuery($request, $sources);
        $stats = new PaymentStats(null, $sources);
        $settings = ClinicSetting::current();

        return Inertia::render('Payments/Index', [
            // Each row with its student/employee discount, if any: the amount,
            // the percentage and the amount after it (2026-10-25, by request).
            'payments' => (clone $query)->latest('paid_at')->paginate(15)->withQueryString()
                ->through(fn (Payment $p) => [
                    ...$p->toArray(),
                    'discount' => $p->patientRegistration?->discount_eligible
                        ? StudentDiscount::breakdown($p->patientRegistration, (float) $p->amount, StudentDiscount::fullAmountFor($p, $settings))
                        : null,
                ]),
            'filters' => $this->filters($request, $sources),
            'scope' => $sources,
            // Income overview (2026-10-12, by request).
            'periods' => $stats->periods(),
            'daily' => $stats->daily(),
            'monthly' => $stats->monthly(),
            'filteredTotal' => (float) (clone $query)->sum('amount'),
            'bySource' => PaymentStats::bySource($query, $sources),
            'currency' => ClinicSetting::current()->clinic_currency,
            'can' => [
                // The lab / tickets grants include printing their report.
                'export' => PaymentScope::sources($request->user(), true) !== [],
                'delete' => (new PermissionManager($request->user()))->can('payments', 'delete'),
                // The printed activity log (2026-11-01): the full payments grant.
                'activity' => (new PermissionManager($request->user()))->can('payments', 'view'),
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
        $sources = PaymentScope::sources($request->user(), true);
        $query = $this->filteredQuery($request, $sources);
        $stats = new PaymentStats(null, $sources);

        $filters = $this->filters($request, $sources);
        $payments = (clone $query)->with(['appointment', 'patientRegistration.service'])->latest('paid_at')->get();
        $settings = ClinicSetting::current();

        return view('print.payments-report', [
            'settings' => $settings,
            'filters' => $filters,
            'scope' => $sources,
            'payments' => $payments,
            // Last page (2026-11-01, by request): who was treated free with a
            // care code, and who got the student/employee discount.
            'supported' => \App\Support\SupportCodes::reportRowsFor($filters, $sources),
            'discounted' => \App\Support\SupportCodes::discountRows($payments, $settings),
            'filteredTotal' => (float) (clone $query)->sum('amount'),
            'bySource' => PaymentStats::bySource($query, $sources),
            'periods' => $stats->periods(),
            'daily' => $stats->daily(),
            'monthly' => $stats->monthly(),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }

    /**
     * The payments activity log, printed (2026-11-01, by request): who
     * added, changed or deleted which payment and when, for the date range
     * of the payments page. Older entries without a snapshot show what is
     * still known of the payment.
     */
    public function activity(Request $request): View
    {
        $from = $request->date('from');
        $to = $request->date('to');

        $logs = ActivityLog::query()
            ->where('module', 'Payment')
            ->when($from, fn ($q) => $q->whereDate('created_at', '>=', $from))
            ->when($to, fn ($q) => $q->whereDate('created_at', '<=', $to))
            ->latest('created_at')
            ->limit(2000)
            ->get();

        $current = Payment::with(['appointment', 'patientRegistration'])
            ->whereIn('id', $logs->pluck('record_id')->filter()->unique())
            ->get()->keyBy('id');

        $rows = $logs->map(function (ActivityLog $log) use ($current) {
            $data = $log->data ? json_decode($log->data, true) : null;
            $snapshot = $data['snapshot'] ?? $current->get($log->record_id)?->activitySnapshot();

            return [
                'at' => $log->created_at,
                'user' => $log->username,
                'role' => $log->user_role,
                'action' => $log->action,
                'payment_id' => $log->record_id,
                'snapshot' => $snapshot,
                'before' => $data['before'] ?? null,
                'changes' => $data['changes'] ?? ($log->action === 'update' && is_array($data) ? $data : null),
            ];
        });

        return view('print.payments-activity', [
            'settings' => ClinicSetting::current(),
            'rows' => $rows,
            'from' => $from?->format('Y-m-d'),
            'to' => $to?->format('Y-m-d'),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }

    /**
     * The search / date range / source filters shared by `index()` and
     * `report()`, within the account's [$sources] (PaymentScope).
     */
    private function filteredQuery(Request $request, ?array $sources)
    {
        $search = $request->string('search')->toString();
        $source = $this->filters($request, $sources)['source'];

        return PaymentScope::apply(Payment::with(['appointment', 'patientRegistration']), $sources)
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

    private function filters(Request $request, ?array $sources): array
    {
        $source = $request->string('source')->toString() ?: null;
        // A source outside the account's is dropped; a single one is fixed.
        if ($sources !== null) {
            $source = count($sources) === 1 ? $sources[0] : (in_array($source, $sources, true) ? $source : null);
        }

        return [
            'search' => $request->string('search')->toString(),
            'from' => $request->string('from')->toString() ?: null,
            'to' => $request->string('to')->toString() ?: null,
            'source' => $source,
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

        // Less the student discount when the patient is eligible (2026-10-25).
        $fee = StudentDiscount::labFee(PatientRegistration::find($validated['patient_registration_id']));
        if (PatientRegistration::whereKey($validated['patient_registration_id'])->whereNotNull('support_code_id')->exists()) {
            return response()->json(['message' => 'هذا المريض '.\App\Support\SupportCodes::LABEL.'، فلا أجور عليه.'], 422);
        }
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
        abort_unless(PaymentScope::allows(PaymentScope::sources($request->user()), $payment), 403);
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
