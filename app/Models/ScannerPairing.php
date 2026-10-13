<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * A phone lent to a computer as its QR scanner (2026-10-12, by request).
 *
 * The computer (web page or Windows app) creates one and shows its QR and
 * six-digit code. The phone opens `/scan/{token}` (from the QR, or by
 * typing the code at `/scan`), needs no login of its own, and posts every
 * code it reads; the computer polls for them. The token is the secret: it
 * is long and random and the pairing expires after `LIFETIME_HOURS`.
 *
 * The computer can also ask the phone for a photo (2026-10-13, the paper
 * case sheet of a task): `photo_request` holds what it is for, the phone's
 * page shows it with a camera button, and the photo arrives as a scan with
 * `photo_path` (local disk, `scanner-photos/{id}/`) for the computer to
 * attach. See TaskInstanceAttachmentController.
 */
class ScannerPairing extends Model
{
    public const LIFETIME_HOURS = 12;

    protected $fillable = ['user_id', 'token', 'code', 'phone_joined_at', 'photo_request', 'expires_at'];

    protected function casts(): array
    {
        return [
            'phone_joined_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public static function open(User $user): self
    {
        // One live pairing per user: opening a new one ends the old.
        static::where('user_id', $user->id)->get()->each->delete();

        do {
            $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        } while (static::active()->where('code', $code)->exists());

        return static::create([
            'user_id' => $user->id,
            'token' => Str::random(48),
            'code' => $code,
            'expires_at' => now()->addHours(self::LIFETIME_HOURS),
        ]);
    }

    protected static function booted(): void
    {
        // Photos the computer never attached go with the pairing.
        static::deleting(fn (self $pairing) => Storage::disk('local')->deleteDirectory($pairing->photoDir()));
    }

    public function photoDir(): string
    {
        return 'scanner-photos/'.$this->id;
    }

    public function scopeActive(Builder $query): Builder
    {
        return $query->where('expires_at', '>', now());
    }

    public static function findActiveByToken(string $token): ?self
    {
        return static::active()->where('token', $token)->first();
    }

    public static function findActiveByCode(string $code): ?self
    {
        return static::active()->where('code', $code)->first();
    }

    public function phoneUrl(): string
    {
        return rtrim(config('app.url'), '/').'/scan/'.$this->token;
    }

    /** What the computer needs to show the pairing and poll for scans. */
    public function forDesktop(): array
    {
        $qr = (new \Endroid\QrCode\Writer\PngWriter())->write(new \Endroid\QrCode\QrCode(
            data: $this->phoneUrl(),
            errorCorrectionLevel: \Endroid\QrCode\ErrorCorrectionLevel::Medium,
            size: 320,
            margin: 10,
        ));

        return [
            'id' => $this->id,
            'code' => $this->code,
            'url' => $this->phoneUrl(),
            'enter_url' => rtrim(config('app.url'), '/').'/scan',
            'qr' => $qr->getDataUri(),
            'phone_joined' => $this->phone_joined_at !== null,
            'expires_at' => $this->expires_at->toIso8601String(),
        ];
    }

    /**
     * Scans newer than `$afterId`, oldest first, for the computer's poll. A
     * photo comes as `photo: true` (attached by its id), not as a code.
     */
    public function scansAfter(int $afterId): array
    {
        return [
            'phone_joined' => $this->phone_joined_at !== null,
            'photo_request' => $this->photo_request,
            'scans' => $this->scans()->where('id', '>', $afterId)->orderBy('id')->limit(50)
                ->get(['id', 'payload'])
                ->map(fn (ScannerScan $scan) => [
                    'id' => $scan->id,
                    'payload' => $scan->payload,
                    'photo' => $scan->payload === ScannerScan::PHOTO,
                ])->all(),
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function scans(): HasMany
    {
        return $this->hasMany(ScannerScan::class);
    }
}
