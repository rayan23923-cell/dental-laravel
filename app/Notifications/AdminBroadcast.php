<?php

namespace App\Notifications;

use App\Models\ClinicSetting;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * A staff-wide announcement composed by super_admin/admin (2026-09-04, by
 * request — "ارسال تنبيهات الى الكل"). Unlike every other notification in
 * this app (`TaskAssigned`, one doctor, triggered by an event), this one is
 * hand-written and sent to many `User` recipients at once — see
 * `AdminBroadcastController::store()`, which loops `Notifier::send()` per
 * recipient rather than adding a "send to many" primitive there, since
 * looping a single-notifiable send is simpler than a parallel API and this
 * is the only place that needs it.
 */
class AdminBroadcast extends Notification
{
    use Queueable;

    public function __construct(public string $title, public string $body)
    {
    }

    public function via(object $notifiable): array
    {
        $channels = ['database'];

        if (ClinicSetting::current()->enable_email && filled($notifiable->email ?? null)) {
            $channels[] = 'mail';
        }

        return $channels;
    }

    /** Read back by Api\NotificationController for the notification inbox (Flutter today; nothing on web reads it yet). */
    public function toArray(object $notifiable): array
    {
        return [
            'title' => $this->title,
            'message' => $this->body,
        ];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $clinic = ClinicSetting::current()->clinic_name;

        return (new MailMessage)
            ->subject("{$this->title} — {$clinic}")
            // `full_name`, not `name` — this notification only ever targets
            // `App\Models\User` (staff), whose name column is `full_name`
            // (unlike `Doctor`'s plain `name`, which is what
            // `TaskAssigned::toMail()`'s own `$notifiable->name` relies on).
            ->greeting("مرحباً {$notifiable->full_name}")
            ->line($this->body)
            ->salutation("تحياتنا، {$clinic}");
    }
}
