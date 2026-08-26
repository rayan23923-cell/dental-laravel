<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SurgeryImage extends Model
{
    protected $table = 'surgery_images';

    public $timestamps = false;

    protected $fillable = [
        'surgery_id',
        'image_path',
        'image_type',
        'description',
        'uploaded_at',
    ];

    protected function casts(): array
    {
        return [
            'uploaded_at' => 'datetime',
        ];
    }

    public function surgery(): BelongsTo
    {
        return $this->belongsTo(Surgery::class);
    }
}
