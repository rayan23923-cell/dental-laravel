<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One active login session (a Sanctum personal access token) — for the
 * Instagram-style "Active sessions" screen (`Api\SessionController`), on
 * both the web Profile page and the Flutter app.
 *
 * `device_type` is derived from `name` (the `device_name` the client sent
 * at login — see `Api\AuthController::login()`'s own `device_name` param
 * and the Flutter side's `_deviceName()`, currently `"<platform> •
 * dental_clinic_app"`) rather than stored as its own column — it's a
 * display-only classification of an existing field, not new data.
 */
class SessionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        /** @var \Laravel\Sanctum\PersonalAccessToken $this */
        $currentToken = $request->user()?->currentAccessToken();

        return [
            'id' => $this->id,
            'device_name' => $this->name,
            'device_type' => $this->deviceType(),
            'ip_address' => $this->ip_address,
            'location' => $this->location,
            'created_at' => $this->created_at,
            'last_used_at' => $this->last_used_at,
            'is_current' => $currentToken !== null && $currentToken->id === $this->id,
        ];
    }

    /**
     * Coarse platform classification from the `"<platform> •
     * dental_clinic_app"` device-name convention — falls back to
     * `'other'` for anything that doesn't match (an API client that
     * didn't follow the convention, or a future platform), so the UI
     * always has a defined icon to show rather than a blank/crashing case.
     */
    private function deviceType(): string
    {
        $prefix = strtolower(explode(' ', (string) $this->name)[0] ?? '');

        return match (true) {
            str_contains($prefix, 'android') => 'android',
            str_contains($prefix, 'ios') => 'ios',
            str_contains($prefix, 'windows') => 'windows',
            str_contains($prefix, 'macos') => 'macos',
            str_contains($prefix, 'linux') => 'linux',
            str_contains($prefix, 'web') => 'web',
            default => 'other',
        };
    }
}
