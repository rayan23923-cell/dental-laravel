<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * YouTube-TV-style pairing alternative (2026-09-09 follow-up, by request):
 * alongside the QR code, the TV also shows a plain 4-digit code a staff
 * member can type into the web system or the app instead of scanning —
 * easier when a camera scan is awkward on a TV setup. No DB-level unique
 * constraint: uniqueness is only meaningful among currently pending
 * (unconfirmed, unexpired) pairings, which `WaitingScreenPairing::
 * createNew()` enforces at generation time — a stale/confirmed pairing's
 * old code is free to be reused by a later one.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('waiting_screen_pairings', function (Blueprint $table) {
            $table->string('code', 4)->after('token');
            $table->index('code');
        });
    }

    public function down(): void
    {
        Schema::table('waiting_screen_pairings', function (Blueprint $table) {
            $table->dropIndex(['code']);
            $table->dropColumn('code');
        });
    }
};
