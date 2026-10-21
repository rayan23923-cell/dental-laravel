<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\PatientRegistration;
use App\Models\Payment;
use App\Models\Service;
use App\Services\PermissionManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A short fingerprint of the patient registrations (2026-10-19, by
 * request: the ticket desk and the lab update by themselves when a
 * patient is registered). The registrations and lab lists, on the web and
 * in the app, ask for it every few seconds and reload only when it
 * changed, so idle screens cost one small query each time.
 */
class RegistrationsStampController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $permissions = new PermissionManager($request->user());
        abort_unless(
            $permissions->can('patients', 'view')
                || $permissions->can('patient_screening', 'view')
                || $permissions->can('patient_screening', 'confirm'),
            403
        );

        // The table has no updated_at, so a checksum of the columns the
        // lists show catches edits, screening results and archiving too.
        $registrations = PatientRegistration::withTrashed()
            ->selectRaw("COUNT(*) AS n, MAX(id) AS last_id, COALESCE(SUM(CRC32(CONCAT_WS('|', id, name, phone, age, service_id, register_day_id, screening_status, screening_checked_at, screening_reused_from, deleted_at))), 0) AS sum")
            ->first();
        $payments = Payment::whereNotNull('patient_registration_id')->selectRaw('COUNT(*) AS n, MAX(id) AS last_id')->first();
        // The services, their prices and the lab fee too (2026-10-21, by
        // request): a price changed in the browser reaches the app's
        // registration form without reopening the app.
        $services = Service::query()
            ->selectRaw("COUNT(*) AS n, COALESCE(SUM(CRC32(CONCAT_WS('|', id, name, price))), 0) AS sum")
            ->first();
        $lab = ClinicSetting::current();

        return response()->json([
            'stamp' => md5(implode('|', [
                $registrations->n, $registrations->last_id, $registrations->sum,
                $payments->n, $payments->last_id,
                $services->n, $services->sum, $lab->lab_fee, $lab->lab_validity_days,
            ])),
        ]);
    }
}
