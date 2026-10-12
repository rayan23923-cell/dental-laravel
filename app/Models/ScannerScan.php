<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** One code a paired phone read; see ScannerPairing. */
class ScannerScan extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = ['scanner_pairing_id', 'payload'];
}
