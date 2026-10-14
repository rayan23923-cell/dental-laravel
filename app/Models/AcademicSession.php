<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AcademicSession extends Model
{
    // Archived instead of deleted (2026-10-14, by request); see App\Support\LinkedRecords.
    use SoftDeletes;

    public $timestamps = false;

    protected $fillable = [
        'name',
        'start_date',
        'end_date',
        'is_active',
        'is_current',
    ];

    protected function casts(): array
    {
        return [
            'start_date' => 'date:Y-m-d',
            'end_date' => 'date:Y-m-d',
            'is_active' => 'boolean',
            'is_current' => 'boolean',
            'created_at' => 'datetime',
        ];
    }

    public function groups(): HasMany
    {
        return $this->hasMany(Group::class);
    }

    public function tasks(): HasMany
    {
        return $this->hasMany(Task::class);
    }

    protected static function booted(): void
    {
        // The single source of truth for "only one active academic year at
        // a time" — previously this was six near-identical "wipe every
        // row, then set this one" blocks copied across
        // AcademicSessionController/Api\AcademicSessionController's
        // store()/update()/setCurrent(). A model hook covers those call
        // sites AND any other write path (tinker, a seeder, a future
        // feature) that the old copy-pasted approach couldn't.
        static::saving(function (self $session) {
            if ($session->is_current) {
                static::query()
                    ->where('id', '!=', $session->id ?? 0)
                    ->update(['is_current' => false]);
            }
        });
    }
}
