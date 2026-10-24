<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Pairing a waiting screen goes with its settings (2026-10-24, by request:
 * "ربط شاشة انتظار" still showed for every account). The earlier grant gave
 * waiting_screen.pair to all staff; keep it only for the accounts that may
 * edit the waiting screen. Others can be given it in the permissions editor.
 */
return new class extends Migration
{
    public function up(): void
    {
        $editors = DB::table('user_permissions')
            ->where('module', 'waiting_screen')->where('permission', 'edit')->where('granted', true)
            ->pluck('user_id');

        DB::table('user_permissions')
            ->where('module', 'waiting_screen')->where('permission', 'pair')
            ->whereNotIn('user_id', $editors)
            ->delete();
    }

    public function down(): void
    {
        // Not restored: the grant to every account was the mistake.
    }
};
