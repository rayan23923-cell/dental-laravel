<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Group;
use App\Models\WaitingScreenSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\WaitingScreenSettingController for the
 * Flutter client (2026-10-17): the public waiting screen's group, page
 * size and rotation. Which stage a TV shows is chosen when pairing it
 * (Api\WaitingScreenPairingController), not here.
 */
class WaitingScreenSettingController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json([
            'data' => [
                'settings' => $this->settings(),
                'groups' => Group::orderBy('name')->with('stage:id,name')->get(['id', 'name', 'stage_id'])
                    ->map(fn (Group $group) => [
                        'id' => $group->id,
                        'name' => $group->name,
                        'stage_name' => $group->stage?->name,
                    ])->values(),
            ],
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'group_id' => ['nullable', 'exists:groups,id'],
            'patients_per_page' => ['required', 'integer', 'min:1', 'max:50'],
            'rotation_seconds' => ['required', 'integer', 'min:3', 'max:300'],
        ]);

        WaitingScreenSetting::current()->update($validated);

        return response()->json(['data' => ['settings' => $this->settings()]]);
    }

    private function settings(): array
    {
        $settings = WaitingScreenSetting::current();

        return [
            'group_id' => $settings->group_id,
            'patients_per_page' => $settings->patients_per_page,
            'rotation_seconds' => $settings->rotation_seconds,
        ];
    }
}
