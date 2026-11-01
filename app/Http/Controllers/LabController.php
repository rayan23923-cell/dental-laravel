<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Support\LabFeeGate;
use App\Support\StudentDiscount;
use App\Support\QrCodeFactory;
use Endroid\QrCode\ErrorCorrectionLevel;
use Endroid\QrCode\QrCode;
use Endroid\QrCode\Writer\PngWriter;
use Illuminate\Contracts\View\View;
use App\Services\PermissionManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "المختبر" — the web twin of the Flutter app's lab screen (2026-10-11).
 * Until now the web app had no lab page of its own: the dashboard's lab
 * card only led to the full patient-registrations list (which also needs
 * `patients,view`). This page is gated by `patient_screening` alone, lists
 * registrations by screening status, and lets lab staff scan a ticket QR
 * or search, then record the result through the existing
 * `patient-registrations.screening` route.
 */
class LabController extends Controller
{
    public function index(Request $request): Response
    {
        $permissions = $this->authorizeLab($request);

        $validated = $request->validate([
            'status' => ['nullable', Rule::in(['pending', 'flagged', 'clear', 'all'])],
            'search' => ['nullable', 'string', 'max:100'],
        ]);
        $status = $validated['status'] ?? 'pending';
        $search = trim($validated['search'] ?? '');

        $settings = ClinicSetting::current();

        $registrations = PatientRegistration::with(['service:id,name', 'registerDay:id,name', 'screeningCheckedBy:id,full_name'])
            ->withExists(['payments as lab_paid' => fn ($q) => $q->where('type', Payment::TYPE_LAB)])
            ->when($status !== 'all', fn ($q) => $q->where('screening_status', $status))
            ->when($search !== '', function ($query) use ($search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('phone', 'like', "%{$search}%");
                });
            })
            ->orderByDesc('created_at')
            ->paginate(20)
            ->withQueryString();
        $this->attachPreviousScreenings($registrations->getCollection());

        return Inertia::render('Lab/Index', [
            'registrations' => $registrations,
            'counts' => PatientRegistration::selectRaw('screening_status, count(*) as total')
                ->groupBy('screening_status')
                ->pluck('total', 'screening_status'),
            'filters' => ['status' => $status, 'search' => $search],
            // A positive fee means the result waits for the lab payment.
            'labFee' => $settings->lab_fee !== null && (float) $settings->lab_fee > 0 ? $settings->lab_fee : null,
            'currency' => $settings->clinic_currency,
            'validityDays' => LabFeeGate::validityDays(),
            'canConfirm' => $permissions->can('patient_screening', 'confirm'),
        ]);
    }

    /**
     * Same ticket-QR payload as `PatientRegistrationController::scan()`,
     * but gated by `patient_screening,view` instead of `patients,view`.
     */
    public function scan(Request $request): JsonResponse
    {
        $this->authorizeLab($request);

        $request->validate(['payload' => ['required', 'string']]);

        $decoded = json_decode($request->string('payload'), true);

        if (! is_array($decoded) || ($decoded['type'] ?? null) !== 'patient_registration' || empty($decoded['id'])) {
            return response()->json(['message' => 'رمز غير صالح — هذا ليس رمز تسجيل مريض.'], 422);
        }

        $registration = PatientRegistration::with(['service:id,name', 'registerDay:id,name', 'screeningCheckedBy:id,full_name'])
            ->withExists(['payments as lab_paid' => fn ($q) => $q->where('type', Payment::TYPE_LAB)])
            ->find($decoded['id']);

        if (! $registration) {
            return response()->json(['message' => 'التسجيل غير موجود.'], 404);
        }
        $this->attachPreviousScreenings(collect([$registration]));

        return response()->json(['data' => $registration]);
    }

    /**
     * Reuse a still-valid earlier clear result (2026-10-12): no new
     * screening and no lab fee, the lab only prints the slip.
     */
    public function reuse(Request $request, PatientRegistration $patientRegistration): JsonResponse
    {
        $permissions = $this->authorizeLab($request);
        abort_unless($permissions->can('patient_screening', 'confirm'), 403);

        if (! LabFeeGate::isPending($patientRegistration)) {
            return response()->json(['message' => LabFeeGate::ALREADY_RECORDED], 422);
        }

        $previous = LabFeeGate::previousScreening($patientRegistration);
        if (! $previous) {
            return response()->json(['message' => 'لا يوجد فحص سابق صالح لهذا المريض.'], 422);
        }

        $patientRegistration->update([
            'screening_status' => 'clear',
            'screening_checked_by' => $request->user()->id,
            'screening_checked_at' => now(),
            'screening_reused_from' => $previous->id,
        ]);

        return response()->json(['data' => $patientRegistration->fresh()]);
    }

    /** Adds `previous_screening` (id + date) to each registration that can reuse one. */
    private function attachPreviousScreenings($registrations): void
    {
        $previous = LabFeeGate::previousScreenings($registrations);
        $settings = ClinicSetting::current();

        foreach ($registrations as $registration) {
            $match = $registration->screening_status === 'pending' ? $previous->get($registration->id) : null;
            $registration->setAttribute('previous_screening', $match ? [
                'id' => $match->id,
                'checked_at' => $match->screening_checked_at,
                'name' => $match->name,
                'phone' => $match->phone,
                'matched_by' => $match->matched_by,
            ] : null);
            // This patient's fee, less the student discount when eligible (2026-10-25).
            $registration->setAttribute('lab_fee_due', StudentDiscount::labFee($registration, $settings));
        }
    }

    /**
     * Printable lab result (2026-10-11): patient details, the recorded
     * result and the same ticket QR, so the slip itself can be scanned at
     * payment. The Lab page opens it right after a result is saved; the
     * QR is inlined so lab-only staff (no `patients,view`) can print it.
     */
    public function print(Request $request, PatientRegistration $patientRegistration): View
    {
        $this->authorizeLab($request);

        $patientRegistration->load(['service', 'registerDay', 'screeningCheckedBy:id,full_name', 'screeningReusedFrom:id,screening_checked_at'])
            ->loadExists(['payments as lab_paid' => fn ($q) => $q->where('type', Payment::TYPE_LAB)])
            ->loadSum(['payments as lab_fee_paid' => fn ($q) => $q->where('type', Payment::TYPE_LAB)], 'amount');

        $qr = (new PngWriter())->write(new QrCode(
            data: QrCodeFactory::payload('patient_registration', $patientRegistration->id),
            errorCorrectionLevel: ErrorCorrectionLevel::Medium,
            size: 300,
            margin: 10,
        ));

        return view('print.lab-result', [
            'settings' => ClinicSetting::current(),
            'registration' => $patientRegistration,
            'qrDataUri' => $qr->getDataUri(),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }

    /**
     * "بدء الفحص" (2026-11-01, by request): the patient's name with a large
     * "هنا توضع العينات" circle, printed when the lab starts the test so the
     * samples are placed on it and never mixed up between patients.
     */
    public function sample(Request $request, PatientRegistration $patientRegistration): View
    {
        $this->authorizeLab($request);

        // The patient's QR (2026-11-01, by request): scanning the sheet when
        // the result is ready opens the patient to pick the result and pay.
        $qr = (new PngWriter())->write(new QrCode(
            data: QrCodeFactory::payload('patient_registration', $patientRegistration->id),
            errorCorrectionLevel: ErrorCorrectionLevel::Medium,
            size: 300,
            margin: 10,
        ));

        return view('print.lab-sample', [
            'settings' => ClinicSetting::current(),
            'registration' => $patientRegistration->load('service'),
            'qrDataUri' => $qr->getDataUri(),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }

    /**
     * Either screening permission opens the lab: the dashboard's lab card
     * is shown on `confirm`, so `view` alone must not be required.
     */
    private function authorizeLab(Request $request): PermissionManager
    {
        $permissions = new PermissionManager($request->user());

        abort_unless(
            $permissions->can('patient_screening', 'view') || $permissions->can('patient_screening', 'confirm'),
            403
        );

        return $permissions;
    }
}
