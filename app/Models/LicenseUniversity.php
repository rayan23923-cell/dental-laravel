<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A university on the licensing portal, with its activation codes (2026-10-17). */
class LicenseUniversity extends Model
{
    protected $fillable = ['name', 'contact', 'notes', 'max_devices'];

    public function licenses(): HasMany
    {
        return $this->hasMany(OfflineLicense::class, 'university_id');
    }

    /** Computers using one of its codes now (a stopped code frees its computer's place). */
    public function activeDevices(?string $exceptMachine = null): int
    {
        return $this->licenses()->whereNotNull('machine_id')->whereNull('revoked_at')
            ->when($exceptMachine, fn ($q) => $q->where('machine_id', '!=', $exceptMachine))
            ->distinct()->count('machine_id');
    }

    /** Whether one more computer (other than this one) may activate. */
    public function hasRoomFor(?string $machine = null): bool
    {
        return $this->max_devices === null || $this->activeDevices($machine) < $this->max_devices;
    }
}
