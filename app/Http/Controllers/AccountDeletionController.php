<?php

namespace App\Http\Controllers;

use App\Models\AccountDeletionRequest;
use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Models\User;
use App\Notifications\AdminBroadcast;
use App\Services\Notifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Asking for an account's deletion (2026-10-28, for the app stores): the
 * public /delete-account page (Google Play's "delete account URL") and the
 * app's "حذف حسابي" button (both stores want it inside the app). Accounts
 * belong to the clinic's administration, so nothing is deleted here: the
 * request is recorded and the admins get a notification to act on it.
 */
class AccountDeletionController extends Controller
{
    public function show()
    {
        return view('legal.delete-account', ['clinic' => ClinicSetting::current()]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'identifier' => ['required', 'string', 'max:191'],
            'contact' => ['nullable', 'string', 'max:191'],
            'reason' => ['nullable', 'string', 'max:2000'],
        ]);

        $this->record([...$data, 'source' => 'web']);

        return redirect()->route('account-deletion.show')->with('sent', true);
    }

    /** POST /api/v1/me/deletion-request — the signed-in account asks for its own deletion. */
    public function storeForAccount(Request $request): JsonResponse
    {
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:2000']]);
        $account = $request->user();

        $this->record([
            'account_type' => $account instanceof Doctor ? 'doctor' : 'staff',
            'account_id' => $account->getKey(),
            'identifier' => $account->username ?: ($account->email ?? (string) $account->getKey()),
            'contact' => $account->email ?? $account->phone ?? null,
            'reason' => $data['reason'] ?? null,
            'source' => 'app',
        ]);

        return response()->json([
            'message' => 'تم إرسال طلب حذف الحساب إلى إدارة العيادة، وسيُنفَّذ خلال 30 يومًا.',
        ], 201);
    }

    private function record(array $data): void
    {
        $request = AccountDeletionRequest::create($data);

        $name = match ($request->account_type) {
            'doctor' => Doctor::find($request->account_id)?->name,
            'staff' => User::find($request->account_id)?->full_name,
            default => null,
        };
        $body = 'طلب حذف الحساب: '.($name ? "{$name} ({$request->identifier})" : $request->identifier)
            .($request->contact ? " — للتواصل: {$request->contact}" : '')
            .($request->reason ? " — السبب: {$request->reason}" : '');

        User::whereIn('role', ['super_admin', 'admin'])->get()
            ->each(fn (User $admin) => Notifier::send($admin, new AdminBroadcast('طلب حذف حساب', $body)));
    }
}
