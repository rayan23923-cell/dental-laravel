<?php

namespace App\Http\Controllers;

use App\Models\Group;
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
 * No `stage_id` here (2026-09-09 follow-up) — which stage a given TV shows
 * is now chosen from the Flutter app when pairing that specific screen
 * (`WaitingScreenPairingController::confirm()`), not a single global
 * setting here. `group_id` stays here: the app pairing flow only ever
 * asked for stage selection, not group.
 */
class WaitingScreenSettingController extends Controller
{
    public function edit(): Response
    {
        return Inertia::render('WaitingScreenSettings/Edit', [
            'settings' => WaitingScreenSetting::current(),
            'groups' => Group::orderBy('name')->with('stage:id,name')->get(['id', 'name', 'stage_id']),
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
