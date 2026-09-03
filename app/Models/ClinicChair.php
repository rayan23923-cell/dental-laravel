<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One physical dental-chair position in the clinic's seating map — see the
 * `create_clinic_chairs_table` migration's own doc comment for why a chair
 * is assigned to a `Group`, not an individual `Doctor`.
 */
class ClinicChair extends Model
{
    protected $fillable = [
        'row_number',
        'column_number',
        'group_id',
        'label',
    ];

    public function group(): BelongsTo
    {
        return $this->belongsTo(Group::class);
    }
}
