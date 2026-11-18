<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The Emirati female voice is the default for calling names, «ميرو» is
 * no longer offered, and nothing is said before the name by default
 * instead of «المريض» (2026-11-18, by request).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->string('voice_name', 20)->default('emirati')->change();
        });
        DB::table('waiting_screen_settings')->where('voice_name', 'miro')->update(['voice_name' => 'emirati']);
        // «المريض» saved as it was the default becomes the new default: nothing.
        DB::table('waiting_screen_settings')->where('voice_ready_before', 'المريض')->update(['voice_ready_before' => null]);
        DB::table('waiting_screen_settings')->where('voice_waiting_before', 'المريض')->update(['voice_waiting_before' => null]);
    }

    public function down(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->string('voice_name', 20)->default('miro')->change();
        });
    }
};
