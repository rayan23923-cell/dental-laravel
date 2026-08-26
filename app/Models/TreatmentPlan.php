<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TreatmentPlan extends Model
{
    protected $table = 'treatment_plans';

    protected $fillable = [
        'chart_id',
        'plan_date',
        'plan_notes',
        'mark',
        'doctor_name',
        'signature',
    ];

    protected function casts(): array
    {
        return [
            'plan_date' => 'date',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    public function dentalChart(): BelongsTo
    {
        return $this->belongsTo(DentalChart::class, 'chart_id');
    }
}
