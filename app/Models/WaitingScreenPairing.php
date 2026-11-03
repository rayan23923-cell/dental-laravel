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
        'name',
        'last_seen_at',
        'device',
        'commands',
    ];

    /**
     * Commands a paired screen accepts from the server (2026-11-03, by
     * request). `reload` is handled by the page itself; the rest need the
     * TV app (it exposes `window.TvApp` to the page).
     */
    public const COMMANDS = ['reload', 'check_update', 'open_on_boot', 'open_on_wake', 'return_minutes'];

    /** Same choices as the TV app's settings page. */
    public const RETURN_MINUTES = [0, 1, 2, 5, 10, 30, 60];

    protected function casts(): array
    {
        return [
            'confirmed_at' => 'datetime',
            'expires_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'device' => 'array',
            'commands' => 'array',
        ];
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function pushCommand(string $type, mixed $value = null): void
    {
        $commands = $this->commands ?? [];
        // One pending command per type: the newest choice wins.
        $commands = array_values(array_filter($commands, fn ($c) => ($c['type'] ?? null) !== $type));
        $commands[] = ['type' => $type, 'value' => $value];
        $this->commands = $commands;
        $this->save();
    }

    /** Hands the queued commands to the screen once and clears them. */
    public function takeCommands(): array
    {
        $commands = $this->commands ?? [];
        if ($commands !== []) {
            $this->forceFill(['commands' => null])->save();
        }

        return $commands;
    }

    /** Remembers what the screen reported and when, writing at most every 30 s. */
    public function touchSeen(?array $device): void
    {
        $changed = $device !== null && $device !== $this->device;
        if (! $changed && $this->last_seen_at && $this->last_seen_at->gt(now()->subSeconds(30))) {
            return;
        }
        $this->last_seen_at = now();
        if ($device !== null) {
            $this->device = $device;
        }
        $this->save();
    }

    public function isOnline(): bool
    {
        return $this->last_seen_at !== null && $this->last_seen_at->gt(now()->subMinute());
    }

    /** What the staff screens list for one paired TV. */
    public function toScreenArray(): array
    {
        $device = $this->device ?? [];

        return [
            'id' => $this->id,
            'name' => $this->name,
            'paired_at' => $this->confirmed_at?->toIso8601String(),
            'last_seen_at' => $this->last_seen_at?->toIso8601String(),
            'online' => $this->isOnline(),
            'tv_app' => ($device['app'] ?? null) === 'tv',
            'version' => $device['version'] ?? null,
            'open_on_boot' => $device['open_on_boot'] ?? null,
            'open_on_wake' => $device['open_on_wake'] ?? null,
            'return_minutes' => $device['return_minutes'] ?? null,
            'overlay' => $device['overlay'] ?? null,
            'pending' => array_column($this->commands ?? [], 'type'),
        ];
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
