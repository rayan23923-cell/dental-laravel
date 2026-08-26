<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class EducationType extends Model
{
    public $timestamps = false;

    protected $fillable = ['id', 'name'];

    public function stages(): HasMany
    {
        return $this->hasMany(Stage::class);
    }
}
