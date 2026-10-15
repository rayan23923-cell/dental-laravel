<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Stage extends Model
{
    // Archived instead of deleted (2026-10-14, by request); see App\Support\LinkedRecords.
    use SoftDeletes;

    public $timestamps = false;

    protected $fillable = ['id', 'name', 'education_type_id'];

    public function educationType(): BelongsTo
    {
        return $this->belongsTo(EducationType::class);
    }

    public function departments(): HasMany
    {
        return $this->hasMany(Department::class);
    }
}
