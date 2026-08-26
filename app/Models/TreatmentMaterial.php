<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TreatmentMaterial extends Model
{
    protected $table = 'treatment_materials';

    public $timestamps = false;

    protected $fillable = [
        'tooth_treatment_id',
        'material_name',
        'material_type',
        'quantity',
        'unit',
        'cost',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function toothTreatment(): BelongsTo
    {
        return $this->belongsTo(ToothTreatment::class);
    }
}
