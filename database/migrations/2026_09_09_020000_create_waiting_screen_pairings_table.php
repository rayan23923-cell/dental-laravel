<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Privacy gate for the public `/waiting-screen` kiosk display (2026-09-09
 * follow-up, by request): the TV no longer shows real patient names to
 * anyone who happens to open the URL — it shows a QR code instead, and
 * only starts showing appointments once a staff member scans that QR from
 * the Flutter app and picks a stage there (`Api\WaitingScreenPairingController`).
 *
 * `expires_at` only matters before `confirmed_at` is set — an unclaimed
 * pairing is abandoned and replaced with a fresh one/QR after it expires
 * (see `WaitingScreenPairing::isStale()`), but a *confirmed* pairing is
 * kept indefinitely so a physical TV doesn't need re-pairing on every
 * page reload. `token` is the QR payload's identifier, unrelated to the
 * row's own auto-increment `id`, so it can be long/opaque
 * (`Str::random(48)`) without it doubling as anything guessable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('waiting_screen_pairings', function (Blueprint $table) {
            $table->id();
            $table->string('token', 64)->unique();
            $table->integer('stage_id')->nullable();
            $table->timestamp('confirmed_at')->nullable();
            $table->timestamp('expires_at');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('waiting_screen_pairings');
    }
};
