<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Service-priced registration (2026-10-12, by request): registration is
 * name + phone + a service from the registration settings, each service
 * with its price; the day is no longer asked. And a lab screening stays
 * valid for `lab_validity_days`: a patient (same phone) with a clear
 * result inside that window is not screened or charged again, the lab
 * only reuses that result and prints the slip (`screening_reused_from`).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('register_services', 'price')) {
            Schema::table('register_services', function (Blueprint $table) {
                $table->decimal('price', 12, 2)->nullable();
            });
        }

        if (! Schema::hasColumn('clinic_settings', 'lab_validity_days')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->unsignedSmallInteger('lab_validity_days')->nullable()->default(90);
            });
        }

        if (! Schema::hasColumn('patients_simple', 'screening_reused_from')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->unsignedInteger('screening_reused_from')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach ([
            'register_services' => 'price',
            'clinic_settings' => 'lab_validity_days',
            'patients_simple' => 'screening_reused_from',
        ] as $table => $column) {
            if (Schema::hasColumn($table, $column)) {
                Schema::table($table, fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
