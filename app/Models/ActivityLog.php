<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ActivityLog extends Model
{
    protected $table = 'user_activity_log';

    const UPDATED_AT = null;

    protected $fillable = [
        'user_id',
        'username',
        'user_role',
        'action',
        'module',
        'description',
        'record_id',
        'data',
        'details',
        'ip_address',
        'request_method',
        'request_url',
        'user_agent',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
            'deleted_at' => 'datetime',
            'delete_after' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
