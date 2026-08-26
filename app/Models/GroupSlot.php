<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class GroupSlot extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'group_id',
        'day',
        'start_time',
        'end_time',
    ];

    public function group(): BelongsTo
    {
        return $this->belongsTo(Group::class);
    }
}
