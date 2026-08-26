<?php

namespace App\Services;

use App\Models\ClinicSetting;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Facades\Log;

/**
 * General gate for outgoing notifications (in-app `database` channel, mail,
 * and — see `PushNotifier` — push).
 *
 * The original's clinic settings carry an `enable_notifications` toggle
 * that **nothing in it ever reads** — no notification of any kind is sent
 * anywhere in that codebase. Notifications are new here, so every send
 * routes through this same flag, giving the setting real meaning instead of
 * leaving it decorative. The mail-specific `enable_email` toggle (plus
 * "does this notifiable even have an email") is *not* checked here — that
 * decision belongs to each notification's own `via()`, since it's specific
 * to the mail channel and shouldn't block channels (like `database`) that
 * have no such prerequisite. See `TaskAssigned::via()`.
 *
 * A delivery failure never breaks the request that triggered it: a failed
 * mail server shouldn't stop a task from being assigned. Failures are
 * logged instead.
 */
class Notifier
{
    public static function enabled(): bool
    {
        return ClinicSetting::current()->enable_notifications;
    }

    public static function send(?object $notifiable, Notification $notification): bool
    {
        if (! $notifiable || ! static::enabled()) {
            return false;
        }

        try {
            $notifiable->notify($notification);

            return true;
        } catch (\Throwable $e) {
            Log::warning('Notification failed', [
                'notification' => $notification::class,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }
}
