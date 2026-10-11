<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
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

        $registrations = PatientRegistration::with(['service:id,name', 'registerDay:id,name', 'screeningCheckedBy:id,name'])
            ->withSum('payments as total_paid', 'amount')
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

        return Inertia::render('Lab/Index', [
            'registrations' => $registrations,
            'counts' => PatientRegistration::selectRaw('screening_status, count(*) as total')
                ->groupBy('screening_status')
                ->pluck('total', 'screening_status'),
            'filters' => ['status' => $status, 'search' => $search],
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

        $registration = PatientRegistration::with(['service:id,name', 'registerDay:id,name', 'screeningCheckedBy:id,name'])
            ->withSum('payments as total_paid', 'amount')
            ->find($decoded['id']);

        if (! $registration) {
            return response()->json(['message' => 'التسجيل غير موجود.'], 404);
        }

        return response()->json(['data' => $registration]);
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

        $patientRegistration->load(['service', 'registerDay', 'screeningCheckedBy:id,name'])
            ->loadSum('payments as total_paid', 'amount');

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
