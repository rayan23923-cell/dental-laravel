<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Department extends Model
{
    public $timestamps = false;

    protected $fillable = ['name', 'stage_id', 'education_type_id'];

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function educationType(): BelongsTo
    {
        return $this->belongsTo(EducationType::class);
    }
}
