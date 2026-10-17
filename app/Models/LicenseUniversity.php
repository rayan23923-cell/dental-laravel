<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A university on the licensing portal, with its activation codes (2026-10-17). */
class LicenseUniversity extends Model
{
    protected $fillable = ['name', 'contact', 'notes'];

    public function licenses(): HasMany
    {
        return $this->hasMany(OfflineLicense::class, 'university_id');
    }
}
