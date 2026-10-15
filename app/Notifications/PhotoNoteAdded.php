<?php

namespace App\Notifications;

use App\Models\TaskInstance;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * Tells a doctor the supervisor wrote a note on a photo of their case
 * (2026-10-15, by request). In-app only (the `database` channel the
 * notification inbox reads), like TaskAssigned without its mail.
 */
class PhotoNoteAdded extends Notification
{
    use Queueable;

    public function __construct(public TaskInstance $instance, public string $note)
    {
    }

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $task = $this->instance->task;

        return [
            'title' => 'ملاحظة على صورة',
            'type' => 'photo_note',
            'message' => "المشرف كتب ملاحظة على صورة مهمة \"{$task?->title}\": {$this->note}",
            'task_instance_id' => $this->instance->id,
            'task_title' => $task?->title,
            'department' => $task?->department?->name,
        ];
    }
}
