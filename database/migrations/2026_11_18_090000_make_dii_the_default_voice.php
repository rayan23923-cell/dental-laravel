<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * «دي» is the default voice for calling names (2026-11-18, by request),
 * after the Emirati one for a few hours the same morning; settings still on
 * that default move with it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->string('voice_name', 20)->default('dii')->change();
        });
        DB::table('waiting_screen_settings')->where('voice_name', 'emirati')->update(['voice_name' => 'dii']);
    }

    public function down(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->string('voice_name', 20)->default('emirati')->change();
        });
    }
};
