<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * In-app notice about a task start request (2026-10-14, by request): a new
 * request for the staff who can review it, or a turned-down one for the
 * doctor (an approval already notifies the doctor through TaskAssigned).
 * The web bell and the app's inbox both read it, with a sound.
 */
class TaskStartRequestNotice extends Notification
{
    use Queueable;

    public function __construct(
        public string $title,
        public string $message,
        public int $requestId,
        public string $kind,
    ) {
    }

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        return [
            'title' => $this->title,
            'message' => $this->message,
            'type' => 'task_start_request',
            'kind' => $this->kind,
            'task_start_request_id' => $this->requestId,
        ];
    }
}
