<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which Piper voice calls the names (2026-11-17, by request): five Arabic
 * voices, «ميرو» by default. See App\Services\Speech\SpeechSynthesizer::VOICES.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->string('voice_name', 20)->default('miro');
        });
    }

    public function down(): void
    {
        Schema::table('waiting_screen_settings', function (Blueprint $table) {
            $table->dropColumn('voice_name');
        });
    }
};
