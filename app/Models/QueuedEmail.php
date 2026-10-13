<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One message waiting for `mail:send-queued`, which sends at most the daily
 * cap per day. See the create_queued_emails_table migration.
 */
class QueuedEmail extends Model
{
    public const KIND_WELCOME = 'welcome_credentials';

    public const STATUS_PENDING = 'pending';

    public const STATUS_SENT = 'sent';

    public const STATUS_FAILED = 'failed';

    protected $fillable = [
        'kind',
        'recipient_email',
        'recipient_name',
        'payload',
        'status',
        'attempts',
        'last_error',
        'sent_at',
    ];

    protected function casts(): array
    {
        return [
            'payload' => 'encrypted:array',
            'sent_at' => 'datetime',
        ];
    }
}
