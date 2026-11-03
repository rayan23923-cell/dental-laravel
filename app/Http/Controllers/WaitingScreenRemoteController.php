<?php

namespace App\Http\Controllers;

use App\Models\WaitingScreenPairing;
use App\Support\WaitingScreenRemote;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

/** Web side of controlling paired waiting screens (2026-11-03), see WaitingScreenRemote. */
class WaitingScreenRemoteController extends Controller
{
    public function command(Request $request, WaitingScreenPairing $pairing): RedirectResponse
    {
        WaitingScreenRemote::command($request, $pairing);

        return back()->with('success', 'تم الإرسال إلى الشاشة.');
    }

    public function update(Request $request, WaitingScreenPairing $pairing): RedirectResponse
    {
        WaitingScreenRemote::rename($request, $pairing);

        return back();
    }

    public function destroy(WaitingScreenPairing $pairing): RedirectResponse
    {
        WaitingScreenRemote::unpair($pairing);

        return back();
    }
}
