<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Controllers\DashboardController as WebDashboardController;
use App\Models\ClinicSetting;
use App\Models\EducationType;
use App\Models\PatientRegistration;
use App\Services\PermissionManager;
use App\Support\PaymentStats;
use App\Models\User;
use App\Support\RolePresets;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The staff dashboard for the app (2026-10-17): the same figures the web
 * dashboard renders (counters, income, task statuses, latest doctors,
 * patients and payments, the "can" flags) and its on-demand tasks per
 * education type, built by the web DashboardController so the two never
 * drift. Same gates as the web page: staff only, and not the desk roles,
 * which the web sends to their own page instead.
 */
class DashboardController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $this->staff($request);

        return response()->json(app(WebDashboardController::class)->dashboardData($user));
    }

    /**
     * The app's home panels by what the user may open (2026-10-18, by
     * request): the lab sees its screening queue, the ticket desk the
     * registrations, the accountant and admins the income. Every staff
     * role may call it; each panel is left out without its grant.
     */
    public function desk(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless($user instanceof User, 403);
        $permissions = new PermissionManager($user);
        $today = now()->startOfDay();
        $panels = [];

        if ($permissions->can('patients', 'view')) {
            $panels['registrations'] = [
                'today' => PatientRegistration::where('created_at', '>=', $today)->count(),
                'total' => PatientRegistration::count(),
            ];
        }

        if ($permissions->can('patient_screening', 'view') || $permissions->can('patient_screening', 'confirm')) {
            $counts = PatientRegistration::selectRaw('screening_status, count(*) as total')
                ->groupBy('screening_status')
                ->pluck('total', 'screening_status');
            $panels['lab'] = [
                'pending' => (int) ($counts['pending'] ?? 0),
                'clear' => (int) ($counts['clear'] ?? 0),
                'flagged' => (int) ($counts['flagged'] ?? 0),
                'checked_today' => PatientRegistration::where('screening_checked_at', '>=', $today)->count(),
            ];
        }

        if (in_array($user->role, self::PAYMENT_ROLES, true)) {
            $panels['payments'] = [
                'periods' => (new PaymentStats())->periods(),
                'currency' => ClinicSetting::current()->clinic_currency,
            ];
        }

        return response()->json(['role' => $user->role, 'panels' => (object) $panels]);
    }

    /** The web's payments roles, plus the accountant, whose work they are. */
    private const PAYMENT_ROLES = ['super_admin', 'admin', 'editor', 'accountant'];

    public function tasksByEducationType(Request $request, EducationType $educationType): JsonResponse
    {
        $this->staff($request);

        return app(WebDashboardController::class)->tasksByEducationType($request, $educationType);
    }

    private function staff(Request $request): User
    {
        $user = $request->user();
        abort_unless($user instanceof User && ! RolePresets::isDeskRole($user->role), 403);

        return $user;
    }
}
