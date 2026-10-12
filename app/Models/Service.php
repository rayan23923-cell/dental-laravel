<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * `register_services` — the reception-desk registration form's service
 * list, each offered on one or more `RegisterDay`s via the normalized
 * `register_day_service_map` pivot. The legacy app also had a
 * `register_day_service` table (day_id -> service **name** varchar) kept
 * in sync as a "legacy/authoritative" cache — deliberately not modeled
 * here; the legacy app's own migration script
 * (`admin/migrate_register_day_service.php`) shows it was already fighting
 * to keep that denormalized copy consistent, and nothing about this
 * feature needs two sources of truth for the same mapping.
 */
class Service extends Model
{
    protected $table = 'register_services';

    public $timestamps = false;

    protected $fillable = ['name', 'price'];

    public function days(): BelongsToMany
    {
        return $this->belongsToMany(RegisterDay::class, 'register_day_service_map', 'service_id', 'day_id');
    }

    public function registrations(): HasMany
    {
        return $this->hasMany(PatientRegistration::class, 'service_id');
    }
}
