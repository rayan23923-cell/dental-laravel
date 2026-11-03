<?php

namespace App\Support;

use App\Models\WaitingScreenPairing;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Validation\Rule;

/**
 * Controlling paired waiting screens from the server (2026-11-03, by
 * request): rename, unpair, and queue commands the screen picks up on its
 * next poll (every few seconds): reload, check for update, open on TV
 * power-on / standby wake, and how soon it returns after someone leaves it.
 * Shared by the web settings page and the app API.
 */
final class WaitingScreenRemote
{
    /** @return Collection<int, array> */
    public static function screens(): Collection
    {
        return WaitingScreenPairing::whereNotNull('confirmed_at')
            ->orderBy('confirmed_at')
            ->get()
            ->map(fn (WaitingScreenPairing $p) => $p->toScreenArray())
            ->values();
    }

    public static function command(Request $request, WaitingScreenPairing $pairing): void
    {
        abort_unless($pairing->isConfirmed(), 404);
        $validated = $request->validate([
            'type' => ['required', Rule::in(WaitingScreenPairing::COMMANDS)],
            'value' => ['nullable'],
        ]);
        $type = $validated['type'];
        $value = null;
        if (in_array($type, ['open_on_boot', 'open_on_wake'], true)) {
            $request->validate(['value' => ['required', 'boolean']]);
            $value = $request->boolean('value');
        } elseif ($type === 'return_minutes') {
            $request->validate(['value' => ['required', 'integer', Rule::in(WaitingScreenPairing::RETURN_MINUTES)]]);
            $value = (int) $request->input('value');
        }
        $pairing->pushCommand($type, $value);
    }

    public static function rename(Request $request, WaitingScreenPairing $pairing): void
    {
        abort_unless($pairing->isConfirmed(), 404);
        $validated = $request->validate(['name' => ['nullable', 'string', 'max:80']]);
        $pairing->update(['name' => $validated['name'] ?: null]);
    }

    /** The TV shows its pairing code again on its next poll. */
    public static function unpair(WaitingScreenPairing $pairing): void
    {
        $pairing->delete();
    }
}
