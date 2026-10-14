<?php

namespace App\Http\Controllers;

use App\Http\Resources\AppNotificationResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;

/**
 * The web notification bell (2026-10-14): the signed-in staff member's or
 * doctor's latest notifications plus the unread count, polled by
 * `NotificationBell.vue`. Same data the app's inbox reads from the API.
 */
class NotificationFeedController extends Controller
{
    public function index(): JsonResponse
    {
        $principal = $this->principal();

        return response()->json([
            'unread' => $principal->unreadNotifications()->count(),
            'data' => AppNotificationResource::collection($principal->notifications()->latest()->limit(15)->get())->resolve(),
        ]);
    }

    public function markAllRead(): JsonResponse
    {
        $this->principal()->unreadNotifications()->update(['read_at' => now()]);

        return response()->json(['message' => 'ok']);
    }

    private function principal()
    {
        return Auth::guard('doctor')->user() ?? request()->user() ?? abort(401);
    }
}
