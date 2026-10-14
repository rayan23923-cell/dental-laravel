<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Department extends Model
{
    // Archived instead of deleted (2026-10-14, by request); see App\Support\LinkedRecords.
    use SoftDeletes;

    public $timestamps = false;

    // pass_percent: the result a doctor needs here (2026-10-14); see App\Support\TaskScoring.
    protected $fillable = ['name', 'stage_id', 'education_type_id', 'pass_percent'];

    protected function casts(): array
    {
        return ['pass_percent' => 'float'];
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function educationType(): BelongsTo
    {
        return $this->belongsTo(EducationType::class);
    }
}
