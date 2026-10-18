<?php

namespace App\Http\Resources;

use App\Models\UserPermission;
use App\Support\PermissionMatrix;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'full_name' => $this->full_name,
            'username' => $this->username,
            'email' => $this->email,
            'phone' => $this->phone,
            'role' => $this->role,
            'status' => $this->status,
            'profile_image' => $this->profile_image,
            // Added alongside the new profile-editing API (2026-08-21) —
            // DoctorResource already exposed a ready-to-use absolute URL
            // (profile_image_url); this one only ever returned the raw
            // storage path, leaving every consumer to build the URL
            // itself. Additive: profile_image is left in place too, since
            // existing callers (e.g. the login response) already read it.
            'profile_image_url' => $this->profile_image ? Storage::disk('public')->url($this->profile_image) : null,
            // null = "follow system/browser language" — see
            // App\Http\Middleware\ResolveLocale (web) and the Flutter
            // LocaleController equivalent.
            'locale' => $this->locale,
            // What the account was granted, as "module.permission" pairs
            // (2026-10-18), so the app shows only the sections it may open.
            'permissions' => $this->role === 'super_admin'
                ? PermissionMatrix::pairs()
                : UserPermission::where('user_id', $this->id)->where('granted', true)->get(['module', 'permission'])
                    ->map(fn ($p) => "{$p->module}.{$p->permission}")->values()->all(),
        ];
    }
}
