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
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
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
}
