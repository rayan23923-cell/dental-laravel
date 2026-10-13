<?php

use App\Services\DefaultGroups;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Groups on/off switch in clinic settings, and group A for every stage
 * with all of its doctors (2026-10-13, by request). See DefaultGroups.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('clinic_settings', 'groups_enabled')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->boolean('groups_enabled')->default(true);
            });
        }

        DefaultGroups::sync();
    }

    public function down(): void
    {
        if (Schema::hasColumn('clinic_settings', 'groups_enabled')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->dropColumn('groups_enabled');
            });
        }
    }
};
