<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Wraps Laravel's built-in `DatabaseNotification` model — `data` is
 * whatever the originating notification's `toArray()` returned (see
 * `App\Notifications\TaskAssigned::toArray()`), spread flat alongside the
 * envelope fields rather than nested, since every consumer today only ever
 * reads one notification type's shape.
 */
class AppNotificationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'read_at' => $this->read_at,
            'created_at' => $this->created_at,
            ...$this->data,
        ];
    }
}
