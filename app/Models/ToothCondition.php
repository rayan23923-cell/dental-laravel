<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ToothCondition extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'dental_chart_id',
        'tooth_number',
        'tooth_position',
        'condition_type',
        'severity',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function dentalChart(): BelongsTo
    {
        return $this->belongsTo(DentalChart::class);
    }
}
