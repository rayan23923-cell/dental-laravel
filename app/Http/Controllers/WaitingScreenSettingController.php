<?php

namespace App\Http\Controllers;

use App\Models\WaitingScreenSetting;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Admin-facing controls for the public waiting-room display
 * (`/waiting-screen`, `Api\WaitingScreenController`). Mirrors
 * `ClinicSettingController`'s singleton edit/update shape.
 *
 * No stages or groups (2026-11-02, by request): the screen shows the lab
 * only, so the page only edits the display-tuning fields. `group_id` is
 * still accepted for old app builds but no longer used by the screen.
 */
class WaitingScreenSettingController extends Controller
{
    public function edit(): Response
    {
        return Inertia::render('WaitingScreenSettings/Edit', [
            'settings' => WaitingScreenSetting::current(),
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        if ($request->input('group_id') === '') {
            $request->merge(['group_id' => null]);
        }

        $validated = $request->validate([
            'group_id' => ['nullable', 'exists:groups,id'],
            'patients_per_page' => ['required', 'integer', 'min:1', 'max:50'],
            'rotation_seconds' => ['required', 'integer', 'min:3', 'max:300'],
        ]);

        WaitingScreenSetting::current()->update($validated);

        return back()->with('success', 'Waiting screen settings updated.');
    }
}
