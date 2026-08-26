<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SurgeryFollowUp extends Model
{
    protected $table = 'surgery_follow_ups';

    public $timestamps = false;

    protected $fillable = [
        'surgery_id',
        'follow_up_date',
        'findings',
        'patient_status',
        'next_appointment',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'follow_up_date' => 'date',
            'next_appointment' => 'date',
            'created_at' => 'datetime',
        ];
    }

    public function surgery(): BelongsTo
    {
        return $this->belongsTo(Surgery::class);
    }
}
