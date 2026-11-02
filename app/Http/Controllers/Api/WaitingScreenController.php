<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\TaskInstance;
use App\Models\WaitingScreenPairing;
use App\Models\WaitingScreenSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Public, unauthenticated read-only feed for the waiting-room appointments
 * display (`/waiting-screen`) — a newer sibling of `TvBoardController`,
 * built on `Appointment`/`case_sheet_doctor_id` (added 2026-09-09) instead
 * of the legacy `Patient`/`group.slots` schedule that endpoint reads.
 *
 * Privacy gate (2026-09-09 follow-up, by request): this endpoint refuses
 * to return any patient data at all until the caller presents a `token`
 * for a *confirmed* `WaitingScreenPairing` — i.e. until a staff member has
 * scanned this TV's QR code from the Flutter app and picked a stage there
 * (`WaitingScreenPairingController::confirm()`). Without one (missing,
 * unknown, or still-pending token), it creates/reuses a pairing row and
 * hands back just its token so the page can render that pairing's QR —
 * see `WaitingScreenPairing::isStale()`'s docblock for why a *confirmed*
 * pairing never expires here even though `expires_at` exists.
 *
 * The confirmed pairing's own `stage_id` decides which stage to show
 * (nullable = every stage) — this replaces `WaitingScreenSetting::stage_id`
 * as the stage filter's source now that stage selection moved into the
 * app. `WaitingScreenSetting` still supplies `group_id` (unchanged, still
 * admin-configured — the app flow only ever asked for stage selection)
 * plus the display-tuning fields (`patients_per_page`/`rotation_seconds`).
 *
 * Registered patients (2026-10-22, by request): besides today's
 * appointments, the screen also lists every patient registered at the
 * desk today (`PatientRegistration`, `patients_simple`) in registration
 * order, with the doctor once one has started their case sheet. A
 * registration already shown through one of today's appointments is not
 * listed twice. The stage filter matches the registration's task stage or
 * its doctor's stage; the group filter only hides a registration whose
 * doctor is outside the group, since an unassigned patient has no group.
 *
 * "بانتظار الفحص" (2026-11-02, by request): patients whose lab samples
 * sheet was printed today ("بدء الفحص") and whose result is still pending
 * are listed separately in `lab_waiting`, in print order, and drop off as
 * soon as the result is recorded. The lab serves every stage, so this
 * list is not stage- or group-filtered.
 *
 * "النتيجة جاهزة للاستلام" (2026-11-02, by request): a patient whose
 * result was recorded today shows in `lab_ready` (the result itself is
 * never shown) until the lab taps "استلام النتيجة" when they collect it.
 * A reused result is collected at once.
 */
class WaitingScreenController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $token = $request->string('token')->toString();
        $pairing = $token ? WaitingScreenPairing::where('token', $token)->first() : null;

        if (! $pairing || $pairing->isStale()) {
            $pairing = WaitingScreenPairing::createNew();
        }

        if (! $pairing->isConfirmed()) {
            return response()->json([
                'paired' => false,
                'token' => $pairing->token,
                // The screen's clock follows the server (2026-11-02).
                'server_time' => now()->getTimestampMs(),
                'timezone' => ClinicSetting::current()->clinic_timezone ?: 'Asia/Baghdad',
                // The YouTube-TV-style alternative to scanning — see
                // WaitingScreenPairing's own docblock.
                'code' => $pairing->code,
            ]);
        }

        $settings = WaitingScreenSetting::current();
        $clinic = ClinicSetting::current();
        // Groups turned off in clinic settings: no group filter, no group name.
        $groupId = ClinicSetting::groupsEnabled() ? $settings->group_id : null;

        $appointments = Appointment::with('caseSheetDoctor')
            ->whereDate('appointment_date', today())
            ->when($pairing->stage_id, fn ($q, $stageId) => $q->whereHas(
                'caseSheetDoctor',
                fn ($dq) => $dq->where('stage_id', $stageId)
            ))
            ->when($groupId, fn ($q, $groupId) => $q->whereHas(
                'caseSheetDoctor.groups',
                fn ($gq) => $gq->where('groups.id', $groupId)
            ))
            ->orderBy('appointment_date')
            ->get();

        $shownRegistrationIds = $appointments->pluck('patient_registration_id')->filter()->all();

        $registrations = PatientRegistration::with([
            'task',
            'taskInstances' => fn ($q) => $q->whereIn('status', ['assigned', 'completed'])
                ->whereNotNull('doctor_id')
                ->latest('assigned_date')
                ->with('doctor.groups'),
        ])
            ->whereDate('created_at', today())
            ->whereNotIn('id', $shownRegistrationIds)
            ->orderBy('created_at')
            ->orderBy('id')
            ->get()
            ->map(fn (PatientRegistration $registration) => [
                'registration' => $registration,
                'doctor' => $registration->taskInstances->first()?->doctor,
            ])
            ->filter(fn ($row) => ! $pairing->stage_id
                || $row['registration']->task?->stage_id == $pairing->stage_id
                || $row['doctor']?->stage_id == $pairing->stage_id)
            ->filter(fn ($row) => ! $groupId
                || ! $row['doctor']
                || $row['doctor']->groups->contains('id', $groupId));

        $appointments = $appointments
            ->map(fn (Appointment $appointment) => [
                'patient_name' => $appointment->full_name,
                'doctor_name' => $appointment->caseSheetDoctor?->name,
            ])
            ->concat($registrations->map(fn ($row) => [
                'patient_name' => $row['registration']->name,
                'doctor_name' => $row['doctor']?->name,
            ]))
            ->values();

        // One lab list (2026-11-02, by request): each patient keeps their
        // place, amber "بانتظار الفحص" turning green "النتيجة جاهزة" once the
        // result is recorded, until "استلام النتيجة".
        // Collected ("استلام النتيجة", allowed at any time) leaves the screen.
        $lab = PatientRegistration::query()
            ->whereNull('lab_result_received_at')
            ->where(fn ($q) => $q
                ->where(fn ($w) => $w->where('screening_status', 'pending')
                    ->whereNotNull('lab_sample_printed_at')
                    ->whereDate('lab_sample_printed_at', today()))
                ->orWhere(fn ($w) => $w->whereIn('screening_status', ['clear', 'flagged'])
                    ->whereNull('lab_result_received_at')
                    ->whereDate('screening_checked_at', today())))
            ->get(['id', 'name', 'screening_status', 'screening_checked_at', 'lab_sample_printed_at'])
            ->map(function (PatientRegistration $registration) {
                $ready = $registration->screening_status !== 'pending';
                $checkedAt = $registration->screening_checked_at
                    ? \Illuminate\Support\Carbon::parse($registration->screening_checked_at)
                    : null;
                $stamp = $registration->lab_sample_printed_at ?? $checkedAt;

                return [
                    'id' => $registration->id,
                    'patient_name' => $registration->name,
                    'status' => $ready ? 'ready' : 'waiting',
                    'since' => ($ready ? $checkedAt : $registration->lab_sample_printed_at)?->format('H:i'),
                    'order' => $stamp?->getTimestamp() ?? 0,
                ];
            })
            ->sortBy([['order', 'asc'], ['id', 'asc']])
            ->values();

        $labRow = fn ($row) => ['patient_name' => $row['patient_name'], 'status' => $row['status'], 'since' => $row['since']];
        $labWaiting = $lab->where('status', 'waiting')->map($labRow)->values();
        $labReady = $lab->where('status', 'ready')->map($labRow)->values();

        return response()->json([
            'paired' => true,
            'token' => $pairing->token,
            // The screen's clock follows the server (2026-11-02, by request):
            // a TV's own clock is often wrong.
            'server_time' => now()->getTimestampMs(),
            'timezone' => ClinicSetting::current()->clinic_timezone ?: 'Asia/Baghdad',
            'clinic_name' => $clinic->clinic_name,
            'logo_url' => $clinic->logoUrl(),
            'stage_name' => $pairing->stage?->name,
            'group_name' => $groupId ? $settings->group?->name : null,
            'patients_per_page' => $settings->patients_per_page,
            'rotation_seconds' => $settings->rotation_seconds,
            'date' => today()->toDateString(),
            'appointments' => $appointments,
            'lab' => $lab->map($labRow)->values(),
            'lab_waiting' => $labWaiting,
            'lab_ready' => $labReady,
        ]);
    }
}
