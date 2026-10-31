<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * An activation code for one offline copy (2026-10-17, by request). Unused
 * until a computer activates with it; from then on it belongs to that
 * computer's machine id and can only be activated there again.
 */
class OfflineLicense extends Model
{
    protected $fillable = ['code', 'university', 'university_id', 'notes', 'machine_id', 'machine_name', 'activated_at', 'last_seen_at', 'installed_build', 'last_ip', 'revoked_at', 'created_by', 'tunnel_slug', 'tunnel_url', 'tunnel_panel_url', 'tunnel_seen_at'];

    protected function casts(): array
    {
        return [
            'activated_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'revoked_at' => 'datetime',
            'tunnel_seen_at' => 'datetime',
        ];
    }

    /**
     * Codes made on the clinic's own page name their university as text: link
     * them to the portal's university of that name, creating it if needed.
     */
    protected static function booted(): void
    {
        static::creating(function (OfflineLicense $license) {
            if (! $license->university_id && $license->university) {
                $license->university_id = LicenseUniversity::firstOrCreate(['name' => $license->university])->id;
            }
        });
    }

    public function universityRecord(): BelongsTo
    {
        return $this->belongsTo(LicenseUniversity::class, 'university_id');
    }

    /** Four groups of four, without letters that read alike (0/O, 1/I/L). */
    public static function newCode(): string
    {
        $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
        do {
            $chars = '';
            for ($i = 0; $i < 16; $i++) {
                $chars .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            $code = implode('-', str_split($chars, 4));
        } while (self::where('code', $code)->exists());

        return $code;
    }

    /**
     * The tunnel counts as online while the panel keeps reporting it (every
     * few minutes, see offline/windows/panel Tunnel.Report).
     */
    public function tunnelOnline(): bool
    {
        return $this->tunnel_url && $this->tunnel_seen_at && $this->tunnel_seen_at->gt(now()->subMinutes(15));
    }

    /** The fixed link on the hosting that leads to this computer's tunnel. */
    public function tunnelLink(string $to = ''): ?string
    {
        // Always on the clinic site (APP_URL), also when shown on the licensing portal's domain.
        return $this->tunnel_slug ? rtrim(config('app.url'), '/').'/go/'.$this->tunnel_slug.($to ? '/'.$to : '') : null;
    }

    public static function normalize(?string $code): string
    {
        $plain = preg_replace('/[^A-Z0-9]/', '', Str::upper((string) $code));

        return implode('-', str_split($plain, 4));
    }
}
