<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * `register_days` — the reception-desk registration form's day list (e.g.
 * "السبت", "الأحد"). Distinct from anything task/academic-session related;
 * see `PatientRegistration`'s docblock for the wider context.
 */
class RegisterDay extends Model
{
    public $timestamps = false;

    protected $fillable = ['name', 'sort_order'];

    public function services(): BelongsToMany
    {
        return $this->belongsToMany(Service::class, 'register_day_service_map', 'day_id', 'service_id');
    }

    /**
     * Day-governed diagnosis ("التشخيص") — see
     * `2026_08_25_120000_create_register_day_task_map_table`'s docblock.
     * Empty for every day until an admin configures at least one, in
     * which case that day's registration form narrows to just these; an
     * unconfigured day stays fully open (see `PatientRegistrationController::store()`).
     */
    public function tasks(): BelongsToMany
    {
        return $this->belongsToMany(Task::class, 'register_day_task_map', 'day_id', 'task_id');
    }

    public function registrations(): HasMany
    {
        return $this->hasMany(PatientRegistration::class, 'register_day_id');
    }
}
