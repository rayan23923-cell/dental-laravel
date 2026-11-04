<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Permanent delete from the archive from one list only (2026-11-04, by
 * request): an archived patient can be deleted from the patients list,
 * the lab list, or both. A part deleted from one list never comes back
 * to it, even if the rest is restored.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->timestamp('registry_deleted_at')->nullable();
            $table->timestamp('lab_deleted_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropColumn(['registry_deleted_at', 'lab_deleted_at']);
        });
    }
};
