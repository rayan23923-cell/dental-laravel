<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Controllers\DashboardController as WebDashboardController;
use App\Models\EducationType;
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

    public function tasksByEducationType(Request $request, EducationType $educationType): JsonResponse
    {
        $this->staff($request);

        return app(WebDashboardController::class)->tasksByEducationType($educationType);
    }

    private function staff(Request $request): User
    {
        $user = $request->user();
        abort_unless($user instanceof User && ! RolePresets::isDeskRole($user->role), 403);

        return $user;
    }
}
