<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Archiving from one list only (2026-11-02, by request): the archive asks
 * whether to take a patient off the patients list, the lab list, or both
 * (both = the existing soft delete).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->timestamp('registry_archived_at')->nullable();
            $table->timestamp('lab_archived_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropColumn(['registry_archived_at', 'lab_archived_at']);
        });
    }
};
