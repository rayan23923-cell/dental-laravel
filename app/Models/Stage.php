<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Stage extends Model
{
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
