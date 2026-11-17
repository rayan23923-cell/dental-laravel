<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Calling patients by name on the waiting screen (2026-11-17, by request):
 * the server turns «المريض … نتيجتك جاهزة» into speech (Piper, or the
 * Windows voice on a Windows server) and the screen plays it, so TVs
 * without text-to-speech can call names too. See App\Support\VoiceCalls.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->boolean('voice_enabled')->default(true);
            $table->string('voice_engine', 10)->default('piper');
            $table->boolean('voice_ready')->default(true);
            $table->string('voice_ready_before', 150)->nullable();
            $table->string('voice_ready_after', 150)->nullable();
            $table->boolean('voice_waiting')->default(false);
            $table->string('voice_waiting_before', 150)->nullable();
            $table->string('voice_waiting_after', 150)->nullable();
            $table->unsignedTinyInteger('voice_repeat')->default(2);
            $table->unsignedTinyInteger('voice_volume')->default(100);
            $table->unsignedTinyInteger('voice_rate')->default(100);
        });
    }

    public function down(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->dropColumn([
                'voice_enabled', 'voice_engine', 'voice_ready', 'voice_ready_before', 'voice_ready_after',
                'voice_waiting', 'voice_waiting_before', 'voice_waiting_after', 'voice_repeat', 'voice_volume', 'voice_rate',
            ]);
        });
    }
};
