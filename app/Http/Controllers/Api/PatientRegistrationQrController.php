<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PatientRegistrationResource;
use App\Models\PatientRegistration;
use App\Support\QrCodeFactory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;

/**
 * The reception-desk ticket QR: printed on the thermal ticket when a
 * patient registers (see flutter_app's `ticket_widget.dart`), scanned at
 * the payment desk to pull up that registration and whether it has been
 * paid.
 *
 * Payload follows the one convention this codebase standardized on —
 * `{"type":"patient_registration","id":N}` — see
 * `Api\TaskInstanceQrController`'s docblock for that history, and
 * `App\Support\QrCodeFactory` for the shared generator.
 */
class PatientRegistrationQrController extends Controller
{
    public function show(Request $request, PatientRegistration $patientRegistration): Response
    {
        return QrCodeFactory::pngResponse(
            QrCodeFactory::payload('patient_registration', $patientRegistration->id),
            (int) $request->integer('size', 300),
        );
    }

    /**
     * Resolve a scanned ticket QR into its registration **plus payment
     * state**, which is the whole point of the desk flow: the clerk needs
     * to see "paid / not paid" before deciding to charge.
     */
    public function scan(Request $request): JsonResponse
    {
        $request->validate(['payload' => ['required', 'string']]);

        $decoded = json_decode($request->string('payload'), true);

        abort_if(
            ! is_array($decoded) || ($decoded['type'] ?? null) !== 'patient_registration' || empty($decoded['id']),
            422,
            'رمز غير صالح — هذا ليس رمز تسجيل مريض.'
        );

        $registration = PatientRegistration::with(['service', 'registerDay'])->findOrFail($decoded['id']);

        return $this->stateResponse($registration);
    }

    /** Same shape as scan(), for polling a known registration by id. */
    public function status(PatientRegistration $patientRegistration): JsonResponse
    {
        $patientRegistration->load(['service', 'registerDay']);

        return $this->stateResponse($patientRegistration);
    }

    /**
     * The lab/reception confirmation step — records whether this patient's
     * infectious-disease/viral-hepatitis screening came back clean. Until
     * this is `clear`, `PatientScreeningGate` blocks payment and starting
     * a task against this registration (see that class).
     */
    public function confirmScreening(Request $request, PatientRegistration $patientRegistration): JsonResponse
    {
        $validated = $request->validate([
            'screening_status' => ['required', Rule::in(['clear', 'flagged'])],
        ]);

        $patientRegistration->update([
            'screening_status' => $validated['screening_status'],
            'screening_checked_by' => $request->user()->id,
            'screening_checked_at' => now(),
        ]);

        return $this->stateResponse($patientRegistration->fresh(['service', 'registerDay']));
    }

    /**
     * `is_paid` is simply "has any payment been recorded against this
     * registration". There is no expected-fee column anywhere in the
     * schema (`register_services` is `(id, name)` only), so a
     * price-aware partially-vs-fully-paid distinction is not derivable
     * today — deliberately not invented here. Adding per-service pricing
     * is a separate decision.
     */
    private function stateResponse(PatientRegistration $registration): JsonResponse
    {
        $payments = $registration->payments()->orderByDesc('paid_at')->get();
        $totalPaid = (float) $payments->sum('amount');

        return response()->json([
            'data' => [
                'registration' => (new PatientRegistrationResource($registration))->resolve(),
                'payments' => $payments->map(fn ($p) => [
                    'id' => $p->id,
                    'amount' => $p->amount,
                    'paid_by' => $p->paid_by,
                    'paid_at' => $p->paid_at,
                ])->values(),
                'total_paid' => $totalPaid,
                'is_paid' => $payments->isNotEmpty(),
            ],
        ]);
    }
}
