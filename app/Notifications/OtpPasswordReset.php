<?php

namespace App\Notifications;

use App\Models\ClinicSetting;
use App\Services\OtpPasswordResetBroker;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * The password-reset code email, replacing the clickable-link
 * `ResetPassword`/`DoctorResetPassword` notifications (2026-08-29, by
 * request) — one class for both guards, since the content doesn't need
 * to differ by account type the way the old link's target route did.
 */
class OtpPasswordReset extends Notification
{
    use Queueable;

    public function __construct(public string $code)
    {
    }

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $clinic = ClinicSetting::current()->clinic_name;

        return (new MailMessage)
            ->subject("رمز إعادة تعيين كلمة المرور — {$clinic}")
            ->greeting('مرحباً')
            ->line('تلقيت هذه الرسالة لأنه تم طلب إعادة تعيين كلمة المرور لحسابك.')
            ->line('رمز التحقق الخاص بك هو:')
            ->line("## {$this->code}")
            ->line('ينتهي هذا الرمز خلال '.OtpPasswordResetBroker::EXPIRY_MINUTES.' دقائق، ولا يمكن استخدامه أكثر من مرة.')
            ->line('إذا لم تطلب إعادة التعيين، فلا حاجة لأي إجراء.')
            ->salutation("تحياتنا، {$clinic}");
    }
}
