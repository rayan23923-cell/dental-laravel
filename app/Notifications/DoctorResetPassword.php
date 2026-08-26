<?php

namespace App\Notifications;

use App\Models\ClinicSetting;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Facades\Config;

/**
 * Password reset link for the `doctor` guard. Mirrors Laravel's built-in
 * reset notification but builds its URL from the doctor routes and is
 * written in Arabic to match the doctor-facing UI.
 */
class DoctorResetPassword extends Notification
{
    use Queueable;

    public function __construct(public string $token)
    {
    }

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $url = url(route('doctor.password.reset', [
            'token' => $this->token,
            'email' => $notifiable->getEmailForPasswordReset(),
        ], false));

        $clinic = ClinicSetting::current()->clinic_name;
        $minutes = Config::get('auth.passwords.doctors.expire', 60);

        return (new MailMessage)
            ->subject("إعادة تعيين كلمة المرور — {$clinic}")
            ->greeting('مرحباً')
            ->line('تلقيت هذه الرسالة لأنه تم طلب إعادة تعيين كلمة المرور لحسابك.')
            ->action('إعادة تعيين كلمة المرور', $url)
            ->line("تنتهي صلاحية هذا الرابط خلال {$minutes} دقيقة.")
            ->line('إذا لم تطلب إعادة التعيين، فلا حاجة لأي إجراء.')
            ->salutation("تحياتنا، {$clinic}");
    }
}
