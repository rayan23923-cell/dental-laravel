<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\ClinicSetting;
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
            ->get()
            ->map(fn (Appointment $appointment) => [
                'patient_name' => $appointment->full_name,
                'doctor_name' => $appointment->caseSheetDoctor?->name,
            ])
            ->values();

        return response()->json([
            'paired' => true,
            'token' => $pairing->token,
            'clinic_name' => $clinic->clinic_name,
            'logo_url' => $clinic->logoUrl(),
            'stage_name' => $pairing->stage?->name,
            'group_name' => $groupId ? $settings->group?->name : null,
            'patients_per_page' => $settings->patients_per_page,
            'rotation_seconds' => $settings->rotation_seconds,
            'date' => today()->toDateString(),
            'appointments' => $appointments,
        ]);
    }
}
