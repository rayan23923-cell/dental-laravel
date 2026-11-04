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
 * scanned this TV's QR code from the Flutter app and confirmed it there
 * (`WaitingScreenPairingController::confirm()`). Without one (missing,
 * unknown, or still-pending token), it creates/reuses a pairing row and
 * hands back just its token so the page can render that pairing's QR —
 * see `WaitingScreenPairing::isStale()`'s docblock for why a *confirmed*
 * pairing never expires here even though `expires_at` exists.
 *
 * No stages or groups (2026-11-02, by request): the screen shows the lab
 * only, so nothing here is filtered by stage or group and the pairing no
 * longer carries one. `WaitingScreenSetting` supplies the display-tuning
 * fields (`patients_per_page`/`rotation_seconds`).
 *
 * Registered patients (2026-10-22, by request): besides today's
 * appointments, the screen also lists every patient registered at the
 * desk today (`PatientRegistration`, `patients_simple`) in registration
 * order, with the doctor once one has started their case sheet. A
 * registration already shown through one of today's appointments is not
 * listed twice.
 *
 * "بانتظار الفحص" (2026-11-02, by request): patients whose lab samples
 * sheet was printed today ("بدء الفحص") and whose result is still pending
 * are listed separately in `lab_waiting`, in print order, and drop off as
 * soon as the result is recorded.
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

        // Remote control (2026-11-03, by request): the screen reports what it
        // is (TV app version and settings) and picks up queued commands.
        $pairing->touchSeen($this->device($request));
        $commands = $pairing->takeCommands();

        $settings = WaitingScreenSetting::current();
        $clinic = ClinicSetting::current();

        $appointments = Appointment::with('caseSheetDoctor')
            ->whereDate('appointment_date', today())
            ->orderBy('appointment_date')
            ->get();

        $shownRegistrationIds = $appointments->pluck('patient_registration_id')->filter()->all();

        $registrations = PatientRegistration::with([
            'task',
            'taskInstances' => fn ($q) => $q->whereIn('status', ['assigned', 'completed'])
                ->whereNotNull('doctor_id')
                ->latest('assigned_date')
                ->with('doctor'),
        ])
            ->whereDate('created_at', today())
            ->whereNotIn('id', $shownRegistrationIds)
            ->orderBy('created_at')
            ->orderBy('id')
            ->get()
            ->map(fn (PatientRegistration $registration) => [
                'registration' => $registration,
                'doctor' => $registration->taskInstances->first()?->doctor,
            ]);

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

        // One lab list (2026-11-02, by request): amber "بانتظار الفحص" once
        // the samples sheet is printed, green "النتيجة جاهزة" once staff
        // press "استلام النتيجة"; the patient leaves when the result is
        // recorded and printed (سليم/غير سليم), i.e. handed over.
        $lab = PatientRegistration::query()
            ->whereNull('lab_archived_at')->whereNull('lab_deleted_at')
            ->where('screening_status', 'pending')
            ->where(fn ($q) => $q->whereNotNull('lab_sample_printed_at')->orWhereNotNull('lab_result_received_at'))
            // Lab filter (2026-11-03, by request): 'today' keeps only patients
            // started or collected since midnight in the clinic's time zone
            // (the app clock is UTC), so the list empties at 12 at night;
            // 'all' lists every patient still pending.
            ->tap(fn ($q) => WaitingScreenSetting::applyLabScope($q, ['lab_sample_printed_at', 'lab_result_received_at']))
            ->get(['id', 'name', 'screening_status', 'lab_result_received_at', 'lab_sample_printed_at'])
            ->map(function (PatientRegistration $registration) {
                $ready = $registration->lab_result_received_at !== null;
                $stamp = $registration->lab_sample_printed_at ?? $registration->lab_result_received_at;

                return [
                    'id' => $registration->id,
                    'patient_name' => $registration->name,
                    'status' => $ready ? 'ready' : 'waiting',
                    'since' => ($ready ? $registration->lab_result_received_at : $registration->lab_sample_printed_at)?->format('H:i'),
                    'order' => $stamp?->getTimestamp() ?? 0,
                ];
            })
            ->sortBy([['order', 'asc'], ['id', 'asc']])
            ->values();

        // `id` lets the screen tell a new card or a card that just turned green
        // apart (glow + chime, 2026-11-02, by request).
        $labRow = fn ($row) => ['id' => $row['id'], 'patient_name' => $row['patient_name'], 'status' => $row['status'], 'since' => $row['since']];
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
            // Lab-only screen (2026-11-02): no stage or group heading.
            'stage_name' => null,
            'group_name' => null,
            'patients_per_page' => $settings->patients_per_page,
            'rotation_seconds' => $settings->rotation_seconds,
            'date' => today()->toDateString(),
            'appointments' => $appointments,
            'lab' => $lab->map($labRow)->values(),
            'lab_waiting' => $labWaiting,
            'lab_ready' => $labReady,
            'commands' => $commands,
        ]);
    }

    /** The `device` JSON the screen sends, trimmed to known keys. */
    private function device(Request $request): ?array
    {
        $raw = $request->input('device');
        if (! is_string($raw) || $raw === '' || strlen($raw) > 2000) {
            return null;
        }
        $data = json_decode($raw, true);
        if (! is_array($data)) {
            return null;
        }
        $keep = ['app', 'version', 'open_on_boot', 'open_on_wake', 'return_minutes', 'overlay', 'model', 'android'];

        return array_intersect_key($data, array_flip($keep));
    }
}
