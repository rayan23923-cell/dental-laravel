<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Remote control of paired waiting screens (2026-11-03, by request): each
 * paired TV gets a name, when it last asked for data, what it reported
 * about itself (TV app version and its auto-start settings) and a queue
 * of commands sent from the server that it picks up on its next poll.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('waiting_screen_pairings', function (Blueprint $table) {
            $table->string('name', 80)->nullable()->after('code');
            $table->timestamp('last_seen_at')->nullable()->after('confirmed_at');
            $table->json('device')->nullable()->after('last_seen_at');
            $table->json('commands')->nullable()->after('device');
        });
    }

    public function down(): void
    {
        Schema::table('waiting_screen_pairings', function (Blueprint $table) {
            $table->dropColumn(['name', 'last_seen_at', 'device', 'commands']);
        });
    }
};
