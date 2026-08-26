<?php

namespace App\Services;

use App\Models\ClinicSetting;
use App\Models\DeviceToken;
use Illuminate\Support\Facades\Log;
use Kreait\Firebase\Contract\Messaging;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification as FirebaseNotification;

/**
 * Push notifications via Firebase Cloud Messaging — the second, optional
 * delivery path alongside the always-on `database` channel
 * (`App\Notifications\TaskAssigned`, read by the Flutter in-app inbox).
 *
 * Deliberately **not** a Laravel notification channel: it's called directly
 * next to `Notifier::send()` at the one call site that needs it
 * (`TaskStarter::start()`), since there's currently only one event that
 * pushes and wiring a full custom channel class for that would be pure
 * ceremony.
 *
 * No real Firebase project exists yet — every step here fails closed
 * (returns without throwing, logs nothing above `warning` level) until
 * `FIREBASE_CREDENTIALS` points at a real service-account file. See
 * README.md's Firebase section for activation steps.
 */
class PushNotifier
{
    public static function send(?object $notifiable, string $title, string $body, array $data = []): void
    {
        if (! $notifiable || ! ClinicSetting::current()->enable_notifications) {
            return;
        }

        $credentials = config('firebase.projects.app.credentials');
        if (blank($credentials) || ! is_string($credentials) || ! file_exists($credentials)) {
            // Not configured yet — expected until a real Firebase project
            // exists. Not a warning: this is the normal state today.
            return;
        }

        $tokens = DeviceToken::where('tokenable_type', $notifiable::class)
            ->where('tokenable_id', $notifiable->id)
            ->pluck('token');

        if ($tokens->isEmpty()) {
            return;
        }

        try {
            $messaging = app(Messaging::class);
            $message = CloudMessage::new()
                ->withNotification(FirebaseNotification::create($title, $body))
                ->withData(array_map(strval(...), $data));

            $messaging->sendMulticast($message, $tokens->all());
        } catch (\Throwable $e) {
            Log::warning('Push notification failed', [
                'notifiable' => $notifiable::class,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
