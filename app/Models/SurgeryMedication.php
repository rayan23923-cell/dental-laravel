<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SurgeryMedication extends Model
{
    protected $table = 'surgery_medications';

    public $timestamps = false;

    protected $fillable = [
        'surgery_id',
        'medication_name',
        'dosage',
        'frequency',
        'duration',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function surgery(): BelongsTo
    {
        return $this->belongsTo(Surgery::class);
    }
}
