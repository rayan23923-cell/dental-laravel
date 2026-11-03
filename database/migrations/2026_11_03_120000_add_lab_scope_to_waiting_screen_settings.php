<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which lab patients the waiting screen lists (2026-11-03, by request):
 * `today` = only today's, the list empties at midnight clinic time;
 * `all` = every patient still pending, whatever the day.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('waiting_screen_settings', 'lab_scope')) {
            Schema::table('waiting_screen_settings', function (Blueprint $table) {
                $table->string('lab_scope', 10)->default('today');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('waiting_screen_settings', 'lab_scope')) {
            Schema::table('waiting_screen_settings', function (Blueprint $table) {
                $table->dropColumn('lab_scope');
            });
        }
    }
};
