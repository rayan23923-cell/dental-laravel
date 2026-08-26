<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DentalFollowUp extends Model
{
    protected $fillable = [
        'dental_chart_id',
        'follow_up_date',
        'follow_up_type',
        'status',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'follow_up_date' => 'datetime',
        ];
    }

    public function dentalChart(): BelongsTo
    {
        return $this->belongsTo(DentalChart::class);
    }
}
