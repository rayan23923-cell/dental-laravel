<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Notifications\AdminBroadcast;
use App\Services\Notifier;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * A one-off staff-wide announcement (2026-09-04, by request — "ارسال
 * تنبيهات الى الكل حسب الصلاحيات الممنوحة"). Confirmed with the user:
 * "الكل" is literal — every `User` (staff) row, no per-recipient
 * permission filter — and "حسب الصلاحيات الممنوحة" just describes who is
 * *allowed to send* (super_admin/admin, matching this controller's own
 * `role:` route gate), not a targeting rule. Doctors are out of scope —
 * confirmed too, and they don't hold `UserPermission` grants the same way
 * staff do regardless.
 *
 * No legacy-app counterpart; no admin UI for composing/sending a
 * notification existed anywhere in this codebase before this (only a
 * decorative `enable_notifications` toggle in Clinic Settings — see
 * `App\Services\Notifier`'s own doc comment).
 */
class AdminBroadcastController extends Controller
{
    public function create(): Response
    {
        return Inertia::render('AdminBroadcast/Create', [
            'recipientCount' => User::count(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'title' => ['required', 'string', 'max:100'],
            'body' => ['required', 'string', 'max:2000'],
        ]);

        $notification = new AdminBroadcast($validated['title'], $validated['body']);

        $sent = 0;
        // A loop over the existing single-notifiable Notifier::send() gate
        // (enable_notifications + per-send failure logging) rather than a
        // new "send to many" primitive — this is the only broadcast this
        // app sends, so a parallel API for it would be unused complexity.
        User::query()->each(function (User $user) use ($notification, &$sent) {
            if (Notifier::send($user, $notification)) {
                $sent++;
            }
        });

        return redirect()
            ->route('admin-broadcast.create')
            ->with('success', "تم إرسال التنبيه إلى {$sent} موظفًا.");
    }
}
