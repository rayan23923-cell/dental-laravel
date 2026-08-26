<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\AppNotificationResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The current authenticated principal's own notifications (Doctor or
 * User — Laravel's `notifications()`/`unreadNotifications()` relations,
 * from the `Notifiable` trait both models already `use`, scope everything
 * to the caller automatically; no separate ownership check needed).
 */
class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $notifications = $request->user()->notifications()->latest()->paginate(20);

        return AppNotificationResource::collection($notifications)->response();
    }

    public function markRead(Request $request, string $id): JsonResponse
    {
        $notification = $request->user()->notifications()->findOrFail($id);
        $notification->markAsRead();

        return response()->json(['data' => ['id' => $notification->id, 'read_at' => $notification->read_at]]);
    }

    public function markAllRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications()->update(['read_at' => now()]);

        return response()->json(['message' => 'ok']);
    }
}
