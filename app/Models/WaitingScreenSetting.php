<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WaitingScreenSetting extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'id',
        'stage_id',
        'group_id',
        'patients_per_page',
        'rotation_seconds',
    ];

    protected function casts(): array
    {
        return [
            'patients_per_page' => 'integer',
            'rotation_seconds' => 'integer',
        ];
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function group(): BelongsTo
    {
        return $this->belongsTo(Group::class);
    }

    public static function current(): self
    {
        return static::firstOrCreate(['id' => 1], [
            'patients_per_page' => 8,
            'rotation_seconds' => 12,
        ]);
    }
}
