<?php

namespace App\Models;

use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Payment extends Model
{
    use LogsActivity;

    public $timestamps = false;

    /** Lab screening fee (2026-10-11) — see the add_lab_fee migration. */
    public const TYPE_LAB = 'lab';

    public const TYPE_SERVICE = 'service';

    protected $fillable = [
        'appointment_id',
        'patient_registration_id',
        'amount',
        'paid_by',
        'paid_at',
        'type',
        // The undiscounted price at the time of payment (2026-11-01).
        'full_amount',
    ];

    protected static function booted(): void
    {
        // Keeps the price of the day with every payment (2026-11-01, by
        // request), so a later price change never alters an old receipt.
        static::creating(function (Payment $payment) {
            if ($payment->full_amount === null) {
                $payment->full_amount = \App\Support\StudentDiscount::currentFullAmountFor($payment) ?? $payment->amount;
            }
        });
    }

    /**
     * What the activity log keeps of a payment (2026-11-01, by request), so
     * a printed log still says what was added, changed or deleted.
     */
    public function activitySnapshot(): array
    {
        $registration = $this->patientRegistration;

        return [
            'patient' => $registration?->name ?? $this->appointment?->full_name,
            'source' => $this->source(),
            'amount' => (float) $this->amount,
            'full_amount' => $this->full_amount !== null ? (float) $this->full_amount : null,
            'paid_by' => $this->paid_by,
            'paid_at' => $this->paid_at?->format('Y-m-d H:i'),
        ];
    }

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'full_amount' => 'decimal:2',
            'paid_at' => 'datetime',
        ];
    }

    public function appointment(): BelongsTo
    {
        return $this->belongsTo(Appointment::class);
    }

    /**
     * The reception-desk registration this payment settles, for payments
     * taken via the ticket-QR desk flow. Mutually exclusive with
     * [appointment] — exactly one of the two is set, enforced in
     * `Api\PaymentController::validatePayment()` (the DB can't express
     * that constraint here; see the migration that added this column).
     */
    public function patientRegistration(): BelongsTo
    {
        // Archived registrations still name their records (2026-10-12).
        return $this->belongsTo(PatientRegistration::class)->withTrashed();
    }

    /** 'lab', 'appointment' or 'registration' (the ticket desk's). */
    public function source(): string
    {
        return $this->type === self::TYPE_LAB ? 'lab' : ($this->appointment_id ? 'appointment' : 'registration');
    }
}
