<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// How many computers each university may activate (2026-10-22, by request),
// set on the licensing portal. Empty means no limit.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('license_universities', function (Blueprint $table) {
            $table->unsignedInteger('max_devices')->nullable()->after('notes');
        });
    }

    public function down(): void
    {
        Schema::table('license_universities', function (Blueprint $table) {
            $table->dropColumn('max_devices');
        });
    }
};
