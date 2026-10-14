<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\HasMany;

class CaseSheetType extends Model
{
    // Archived instead of deleted (2026-10-14, by request); see App\Support\LinkedRecords.
    use SoftDeletes;

    protected $fillable = [
        'type_code',
        'name_ar',
        'name_en',
        'icon',
        'color',
        'page_url',
        'description',
        'is_active',
        'display_order',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
        ];
    }

    public function tasks(): HasMany
    {
        return $this->hasMany(Task::class);
    }
}
