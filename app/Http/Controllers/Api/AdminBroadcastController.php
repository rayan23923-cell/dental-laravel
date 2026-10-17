<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Notifications\AdminBroadcast;
use App\Services\Notifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\AdminBroadcastController for the Flutter
 * client (2026-10-17): one announcement to every staff `User`, through
 * the same Notifier::send() gate. See the web controller for who counts
 * as "everyone".
 */
class AdminBroadcastController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json(['data' => ['recipient_count' => User::count()]]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'title' => ['required', 'string', 'max:100'],
            'body' => ['required', 'string', 'max:2000'],
        ]);

        $notification = new AdminBroadcast($validated['title'], $validated['body']);

        $sent = 0;
        User::query()->each(function (User $user) use ($notification, &$sent) {
            if (Notifier::send($user, $notification)) {
                $sent++;
            }
        });

        return response()->json([
            'message' => "تم إرسال التنبيه إلى {$sent} موظفًا.",
            'data' => ['sent' => $sent],
        ]);
    }
}
