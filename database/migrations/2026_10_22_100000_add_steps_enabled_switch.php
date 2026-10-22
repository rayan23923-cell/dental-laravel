<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "تعبئة الخطوات" switched on or off for the whole system (2026-10-22, by
 * request): when off, a case's steps are hidden everywhere and can't be
 * signed. On, as before. See App\Support\FormSettings.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->boolean('steps_enabled')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn('steps_enabled');
        });
    }
};
