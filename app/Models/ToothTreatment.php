<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ToothTreatment extends Model
{
    protected $fillable = [
        'dental_chart_id',
        'tooth_number',
        'tooth_position',
        'treatment_type',
        'treatment_status',
        'treatment_notes',
        'treatment_date',
    ];

    protected function casts(): array
    {
        return [
            'treatment_date' => 'datetime',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function dentalChart(): BelongsTo
    {
        return $this->belongsTo(DentalChart::class);
    }

    public function materials(): HasMany
    {
        return $this->hasMany(TreatmentMaterial::class);
    }
}
