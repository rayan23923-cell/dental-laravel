<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Archiving instead of deleting registrations (2026-10-12, by request):
 * deleting a patient now only stamps `deleted_at` (Eloquent soft delete),
 * so their payments keep their name and the payment totals stay exact.
 * Archived patients can be listed and restored from the registry.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('patients_simple', 'deleted_at')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->timestamp('deleted_at')->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('patients_simple', 'deleted_at')) {
            Schema::table('patients_simple', fn (Blueprint $t) => $t->dropColumn('deleted_at'));
        }
    }
};
