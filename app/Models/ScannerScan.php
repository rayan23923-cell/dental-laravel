<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One code a paired phone read, or a photo it took (`photo_path`); see ScannerPairing. */
class ScannerScan extends Model
{
    public const UPDATED_AT = null;

    /** The payload of a photo, which is in `photo_path` until attached. */
    public const PHOTO = '[photo]';

    protected $fillable = ['scanner_pairing_id', 'payload', 'photo_path'];

    public function pairing(): BelongsTo
    {
        return $this->belongsTo(ScannerPairing::class, 'scanner_pairing_id');
    }
}
