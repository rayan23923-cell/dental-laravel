<?php

namespace App\Notifications;

use App\Models\ClinicSetting;
use App\Models\TaskInstance;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Notifies a doctor when a task is started for them — both an in-app
 * (`database` channel, read by the Flutter notification inbox) and, when
 * configured, an email. The original app sends no mail at all (its
 * `enable_email` column is a flag nothing reads); mail dispatch is gated on
 * that same flag here so the setting finally means something. `database` is
 * unconditional (beyond the general `enable_notifications` toggle checked in
 * `Notifier::send()`) — it has no email-specific prerequisite, unlike mail.
 */
class TaskAssigned extends Notification
{
    use Queueable;

    public function __construct(public TaskInstance $instance)
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

    /**
     * The database channel's payload — read back by
     * `Api\NotificationController::index()` / `AppNotificationResource`
     * for the Flutter notification inbox.
     */
    public function toArray(object $notifiable): array
    {
        $task = $this->instance->task;

        return [
            'title' => 'مهمة جديدة',
            'message' => "تم بدء مهمة \"{$task->title}\" لك.",
            'task_instance_id' => $this->instance->id,
            'task_title' => $task->title,
            'department' => $task->department?->name,
        ];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $task = $this->instance->task;
        $clinic = ClinicSetting::current()->clinic_name;

        return (new MailMessage)
            ->subject("مهمة جديدة مخصصة لك — {$clinic}")
            ->greeting("مرحباً {$notifiable->name}")
            ->line('تم تخصيص مهمة جديدة لك:')
            ->line("**{$task->title}**")
            ->line('القسم: '.($task->department?->name ?? '—'))
            ->line('المطلوب: '.$task->required_count)
            ->when($this->instance->notes, fn ($m) => $m->line('ملاحظات: '.$this->instance->notes))
            ->action('عرض مهامي', url(route('doctor.dashboard', absolute: false)))
            ->salutation("تحياتنا، {$clinic}");
    }
}
