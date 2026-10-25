<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\PatientRegistrationResource;
use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\User;
use App\Services\PermissionManager;
use App\Support\LabFeeGate;
use App\Support\StudentDiscount;
use App\Support\QrCodeFactory;
use App\Support\RegistrationPaymentState;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;

/**
 * "المختبر" for the app (2026-10-17) — the Sanctum twin of the web
 * `App\Http\Controllers\LabController`: the registrations list by
 * screening status, the ticket-QR scan, one registration's state and its
 * QR image. Gated like the web page, by either `patient_screening`
 * permission alone, so the `lab` role (which has nothing else) can use
 * the whole lab screen. Recording a result keeps using
 * `POST /patient-registrations/{id}/screening` (and `/screening/reuse`),
 * already gated `patient_screening,confirm`.
 */
class LabController extends Controller
{
    private const RELATIONS = ['service', 'registerDay', 'screeningCheckedBy:id,full_name', 'screeningReusedFrom:id,screening_checked_at'];

    public function index(Request $request): JsonResponse
    {
        $permissions = $this->authorizeLab($request);

        $validated = $request->validate([
            'status' => ['nullable', Rule::in(['pending', 'flagged', 'clear', 'all'])],
            'search' => ['nullable', 'string', 'max:100'],
        ]);
        $status = $validated['status'] ?? 'pending';
        $search = trim($validated['search'] ?? '');

        $settings = ClinicSetting::current();

        $registrations = PatientRegistration::with(['service', 'registerDay', 'screeningCheckedBy:id,full_name'])
            ->withExists(['payments as lab_paid' => fn ($q) => $q->where('type', Payment::TYPE_LAB)])
            ->when($status !== 'all', fn ($q) => $q->where('screening_status', $status))
            ->when($search !== '', function ($query) use ($search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('phone', 'like', "%{$search}%");
                });
            })
            ->orderByDesc('created_at')
            ->paginate(20);

        $previous = LabFeeGate::previousScreenings($registrations->getCollection());
        $registrations->setCollection($registrations->getCollection()->map(function (PatientRegistration $r) use ($previous, $settings) {
            $match = $r->screening_status === 'pending' ? $previous->get($r->id) : null;

            return (new PatientRegistrationResource($r))->resolve() + [
                'lab_paid' => (bool) $r->lab_paid,
                // This patient's fee, less the student discount when eligible (2026-10-25).
                'lab_fee_due' => StudentDiscount::labFee($r, $settings),
                'previous_screening' => $match ? [
                    'id' => $match->id,
                    'checked_at' => $match->screening_checked_at,
                    'name' => $match->name,
                    'phone' => $match->phone,
                    'matched_by' => $match->matched_by,
                ] : null,
            ];
        }));

        $counts = PatientRegistration::selectRaw('screening_status, count(*) as total')
            ->groupBy('screening_status')
            ->pluck('total', 'screening_status')
            ->map(fn ($v) => (int) $v);

        return response()->json([
            'data' => $registrations->items(),
            'meta' => [
                'current_page' => $registrations->currentPage(),
                'last_page' => $registrations->lastPage(),
                'total' => $registrations->total(),
                'counts' => (object) $counts->all(),
                'lab_fee' => $settings->lab_fee !== null && (float) $settings->lab_fee > 0 ? (float) $settings->lab_fee : null,
                'currency' => $settings->clinic_currency,
                'validity_days' => LabFeeGate::validityDays(),
                'can_confirm' => $permissions->can('patient_screening', 'confirm'),
            ],
        ]);
    }

    /** Same payload and response as `POST /patient-registrations/scan`, lab-gated. */
    public function scan(Request $request): JsonResponse
    {
        $this->authorizeLab($request);

        $request->validate(['payload' => ['required', 'string']]);
        $decoded = json_decode($request->string('payload'), true);

        if (! is_array($decoded) || ($decoded['type'] ?? null) !== 'patient_registration' || empty($decoded['id'])) {
            return response()->json(['message' => 'رمز غير صالح — هذا ليس رمز تسجيل مريض.'], 422);
        }

        $registration = PatientRegistration::with(self::RELATIONS)->find($decoded['id']);
        if (! $registration) {
            return response()->json(['message' => 'التسجيل غير موجود.'], 404);
        }

        return $this->stateResponse($registration);
    }

    /** One registration's lab/payment state — opened from a list row. */
    public function show(Request $request, PatientRegistration $patientRegistration): JsonResponse
    {
        $this->authorizeLab($request);

        return $this->stateResponse($patientRegistration->load(self::RELATIONS));
    }

    /** The ticket QR for the printed lab slip, without needing `patients,view`. */
    public function qr(Request $request, PatientRegistration $patientRegistration): Response
    {
        $this->authorizeLab($request);

        return QrCodeFactory::pngResponse(
            QrCodeFactory::payload('patient_registration', $patientRegistration->id),
            (int) $request->integer('size', 300),
        );
    }

    private function stateResponse(PatientRegistration $registration): JsonResponse
    {
        return response()->json([
            'data' => RegistrationPaymentState::build(
                $registration,
                (new PatientRegistrationResource($registration))->resolve(),
            ),
        ]);
    }

    /** Either screening permission opens the lab, as on the web. Staff only. */
    private function authorizeLab(Request $request): PermissionManager
    {
        $user = $request->user();
        abort_unless($user instanceof User, 403, 'لا تملك صلاحية لهذا الإجراء.');

        $permissions = new PermissionManager($user);
        abort_unless(
            $permissions->can('patient_screening', 'view') || $permissions->can('patient_screening', 'confirm'),
            403,
            'لا تملك صلاحية لهذا الإجراء.'
        );

        return $permissions;
    }
}
