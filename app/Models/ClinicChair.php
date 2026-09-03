<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One physical dental-chair position in the clinic's seating map. A chair
 * can be assigned at the group level (`group_id` only — a block of seats
 * for a group, no per-doctor distinction) or at the individual-doctor
 * level (`group_id` + `doctor_id` together, added 2026-09-04 by request —
 * "كل كرسي لاسم طبيب معين" — see `ClinicChairController::assignGroup()`
 * for how a group's doctors get spread across chairs).
 */
class ClinicChair extends Model
{
    protected $fillable = [
        'row_number',
        'column_number',
        'group_id',
        'doctor_id',
        'label',
    ];

    public function group(): BelongsTo
    {
        return $this->belongsTo(Group::class);
    }

    public function doctor(): BelongsTo
    {
        return $this->belongsTo(Doctor::class);
    }
}
