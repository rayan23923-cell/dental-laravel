<?php

namespace App\Http\Controllers;

use App\Models\OfflineLicense;
use App\Support\OfflineLicensing;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Activation codes for offline copies (2026-10-17, by request), one per
 * university copy. Super admins of the hosted system create them here and
 * see which are used and on which computer.
 */
class OfflineLicenseController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('OfflineLicenses/Index', [
            // With the fixed links to each computer over the internet (2026-10-31, by request).
            'licenses' => OfflineLicense::orderByDesc('id')->get()->map(fn (OfflineLicense $l) => $l->toArray() + [
                'tunnel_online' => $l->tunnelOnline(),
                'tunnel_link' => $l->tunnelLink(),
                'tunnel_panel_link' => $l->tunnel_panel_url ? $l->tunnelLink('control') : null,
            ]),
            'latest' => OfflineLicensing::latestBuild(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'university' => ['required', 'string', 'max:255'],
            'count' => ['required', 'integer', 'min:1', 'max:50'],
            'notes' => ['nullable', 'string', 'max:255'],
        ]);

        for ($i = 0; $i < $data['count']; $i++) {
            OfflineLicense::create([
                'code' => OfflineLicense::newCode(),
                'university' => $data['university'],
                'notes' => $data['notes'] ?? null,
                'created_by' => $request->user()->id,
            ]);
        }

        return back()->with('success', $data['count'] > 1 ? 'تم إنشاء '.$data['count'].' رموز.' : 'تم إنشاء الرمز.');
    }

    /** Free the code for another computer, or stop / restart it. */
    public function update(Request $request, OfflineLicense $offlineLicense): RedirectResponse
    {
        $action = $request->validate(['action' => ['required', 'in:release,revoke,restore']])['action'];

        $offlineLicense->forceFill(match ($action) {
            'release' => ['machine_id' => null, 'machine_name' => null, 'activated_at' => null],
            'revoke' => ['revoked_at' => now()],
            'restore' => ['revoked_at' => null],
        })->save();

        return back()->with('success', 'تم الحفظ.');
    }

    public function destroy(OfflineLicense $offlineLicense): RedirectResponse
    {
        $offlineLicense->delete();

        return back()->with('success', 'تم حذف الرمز.');
    }
}
