<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\HasMany;

class EducationType extends Model
{
    // Archived instead of deleted (2026-10-14, by request); see App\Support\LinkedRecords.
    use SoftDeletes;

    public $timestamps = false;

    protected $fillable = ['id', 'name'];

    public function stages(): HasMany
    {
        return $this->hasMany(Stage::class);
    }
}
