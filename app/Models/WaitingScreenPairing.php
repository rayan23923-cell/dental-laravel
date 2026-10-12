<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

class WaitingScreenPairing extends Model
{
    protected $fillable = [
        'token',
        'code',
        'stage_id',
        'confirmed_at',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'confirmed_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function isConfirmed(): bool
    {
        return $this->confirmed_at !== null;
    }

    /** Only meaningful before confirmation — see this class's docblock. */
    public function isStale(): bool
    {
        return ! $this->isConfirmed() && now()->greaterThan($this->expires_at);
    }

    /** Find the pairing a just-typed 4-digit code refers to, if any. */
    public static function findPendingByCode(string $code): ?self
    {
        return static::where('code', $code)
            ->whereNull('confirmed_at')
            ->where('expires_at', '>', now())
            ->first();
    }

    public static function createNew(): self
    {
        return static::create([
            'token' => Str::random(48),
            'code' => static::generateUniqueCode(),
            'expires_at' => now()->addMinutes(10),
        ]);
    }

    /**
     * Only ~10000 possible codes, so uniqueness is checked against
     * currently pending pairings only (see this class's docblock) — with a
     * handful of TVs waiting to be paired at once, collisions are rare
     * enough that a plain retry loop is simpler than reserving ranges.
     */
    private static function generateUniqueCode(): string
    {
        do {
            $code = str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        } while (static::findPendingByCode($code) !== null);

        return $code;
    }
}
