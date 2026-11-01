<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A care code, "رمز الرعاية" (2026-11-01, by request): a one-time 5-digit
 * code printed on a card that makes one registration's service and lab test
 * free. Active until used or stopped. See App\Support\SupportCodes.
 */
class SupportCode extends Model
{
    public const ACTIVE = 'active';
    public const USED = 'used';
    public const DISABLED = 'disabled';

    protected $fillable = [
        'code', 'batch', 'note', 'created_by', 'disabled_at', 'disabled_by',
        'used_at', 'patient_registration_id', 'used_by', 'waived_service', 'waived_lab',
    ];

    protected function casts(): array
    {
        return [
            'batch' => 'integer',
            'disabled_at' => 'datetime',
            'used_at' => 'datetime',
            'waived_service' => 'float',
            'waived_lab' => 'float',
        ];
    }

    public function registration(): BelongsTo
    {
        return $this->belongsTo(PatientRegistration::class, 'patient_registration_id')->withTrashed();
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function status(): string
    {
        return match (true) {
            $this->used_at !== null => self::USED,
            $this->disabled_at !== null => self::DISABLED,
            default => self::ACTIVE,
        };
    }

    public function scopeInStatus($query, ?string $status)
    {
        return match ($status) {
            self::ACTIVE => $query->whereNull('used_at')->whereNull('disabled_at'),
            self::USED => $query->whereNotNull('used_at'),
            self::DISABLED => $query->whereNull('used_at')->whereNotNull('disabled_at'),
            default => $query,
        };
    }
}
