<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\PermissionManager;
use App\Services\SupervisorCode;
use App\Support\FormSettings;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "إعدادات النماذج" (2026-10-22, by request), opened from task progress:
 * paper or electronic forms, grades shown to students, and the supervisor
 * code with the supervisor's own current code. JSON for the app, a page
 * for the web; see App\Support\FormSettings and App\Services\SupervisorCode.
 */
class FormSettingsController extends Controller
{
    public function page(Request $request): Response
    {
        return Inertia::render('FormSettings/Index', $this->payload($request->user()));
    }

    public function show(Request $request): JsonResponse
    {
        return response()->json($this->payload($request->user()));
    }

    public function update(Request $request): JsonResponse
    {
        abort_unless($this->can($request->user(), 'form_settings'), 403);

        return response()->json(['settings' => FormSettings::save($request->validate(FormSettings::rules()))]);
    }

    /** The signed-in supervisor's code now (refreshed by the clients as it changes). */
    public function myCode(Request $request): JsonResponse
    {
        abort_unless($this->can($request->user(), 'supervisor_code'), 403);

        return response()->json([...SupervisorCode::current($request->user()), 'enabled' => FormSettings::get()['supervisor_code_enabled']]);
    }

    /** What a student's screens follow: the forms on offer, grades and the code. */
    public function forDoctor(): JsonResponse
    {
        $settings = FormSettings::get();

        return response()->json([
            'electronic_forms_enabled' => $settings['electronic_forms_enabled'],
            'paper_forms_enabled' => $settings['paper_forms_enabled'],
            'show_grades' => $settings['show_grades_to_doctors'],
            'supervisor_code_enabled' => $settings['supervisor_code_enabled'],
            'supervisor_code_actions' => $settings['supervisor_code_enabled'] ? $settings['supervisor_code_actions'] : [],
        ]);
    }

    private function payload(User $user): array
    {
        $hasCode = $this->can($user, 'supervisor_code');

        return [
            'settings' => FormSettings::get(),
            'canEdit' => $this->can($user, 'form_settings'),
            'myCode' => $hasCode ? SupervisorCode::current($user) : null,
        ];
    }

    private function can(?User $user, string $permission): bool
    {
        return $user instanceof User && (new PermissionManager($user))->can('task_progress', $permission);
    }
}
