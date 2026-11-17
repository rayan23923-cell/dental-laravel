<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * `lab_services` (2026-11-17, by request): the lab's own priced services,
 * such as «فحص المختبر» for 2,000. The lab registers a patient who came
 * for the test only against one of them; the patient then goes through
 * the lab as usual and the price is booked as a lab payment when the
 * result is recorded (App\Support\LabFeeGate). Kept apart from
 * App\Models\Service, the reception form's services, so the reception
 * never offers them. A service with patients is switched off, not deleted.
 */
class LabService extends Model
{
    protected $fillable = ['name', 'price', 'active', 'sort', 'created_by'];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'active' => 'boolean',
            'sort' => 'integer',
        ];
    }

    public function registrations(): HasMany
    {
        return $this->hasMany(PatientRegistration::class);
    }

    public function scopeOrdered(Builder $query): Builder
    {
        return $query->orderBy('sort')->orderBy('name');
    }

    /** What the lab screens list and the forms offer. */
    public function toListArray(): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'price' => (float) $this->price,
            'active' => (bool) $this->active,
            'patients' => (int) ($this->registrations_count ?? 0),
        ];
    }
}
