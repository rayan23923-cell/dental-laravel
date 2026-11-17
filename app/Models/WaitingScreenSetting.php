<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WaitingScreenSetting extends Model
{
    public $timestamps = false;

    // Single row with id 1 (tinyint, not auto-increment). Without this the
    // model took lastInsertId (0) as its id after firstOrCreate, so a save
    // in the same request as the create updated nothing.
    public $incrementing = false;

    protected $fillable = [
        'id',
        'stage_id',
        'group_id',
        'patients_per_page',
        'rotation_seconds',
        'lab_scope',
        // Calling names by voice (2026-11-17), see App\Support\VoiceCalls.
        'voice_enabled',
        'voice_engine',
        'voice_ready',
        'voice_ready_before',
        'voice_ready_after',
        'voice_waiting',
        'voice_waiting_before',
        'voice_waiting_after',
        'voice_repeat',
        'voice_volume',
        'voice_rate',
    ];

    /** Lab list on the screen (2026-11-03): today's only (empties at midnight clinic time) or all pending. */
    public const LAB_SCOPES = ['today', 'all'];

    protected function casts(): array
    {
        return [
            'patients_per_page' => 'integer',
            'rotation_seconds' => 'integer',
            'voice_enabled' => 'boolean',
            'voice_ready' => 'boolean',
            'voice_waiting' => 'boolean',
            'voice_repeat' => 'integer',
            'voice_volume' => 'integer',
            'voice_rate' => 'integer',
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

    /** Midnight today in the clinic's time zone, as UTC (the app clock). */
    public static function clinicDayStart(): \Illuminate\Support\Carbon
    {
        return \Illuminate\Support\Carbon::now(ClinicSetting::current()->clinic_timezone ?: 'Asia/Baghdad')->startOfDay()->utc();
    }

    /**
     * With 'today' (2026-11-03, by request), keeps lab rows where any of
     * [columns] falls on today (clinic time), so the waiting screen empties
     * at 12 at night. The app clock is UTC, so a plain whereDate(today())
     * would switch days at 3 am Baghdad time.
     */
    public static function applyLabScope($query, array $columns)
    {
        if ((static::current()->lab_scope ?: 'today') === 'all') {
            return $query;
        }
        $start = static::clinicDayStart();

        return $query->where(function ($w) use ($columns, $start) {
            foreach ($columns as $column) {
                $w->orWhere($column, '>=', $start);
            }
        });
    }

    public static function current(): self
    {
        return static::firstOrCreate(['id' => 1], [
            'patients_per_page' => 8,
            'rotation_seconds' => 12,
            'lab_scope' => 'today',
        ]);
    }
}
