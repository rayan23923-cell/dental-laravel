<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lab screening fee (2026-10-11): a fixed amount set in clinic settings,
 * paid as its own payment (`payments.type = 'lab'`) before the lab
 * screens the patient — so, unlike service payments, it is not blocked by
 * `PatientScreeningGate`.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('clinic_settings', 'lab_fee')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->decimal('lab_fee', 12, 2)->nullable();
            });
        }

        if (! Schema::hasColumn('payments', 'type')) {
            Schema::table('payments', function (Blueprint $table) {
                $table->string('type', 20)->default('service')->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('payments', 'type')) {
            Schema::table('payments', function (Blueprint $table) {
                $table->dropIndex(['type']);
                $table->dropColumn('type');
            });
        }

        if (Schema::hasColumn('clinic_settings', 'lab_fee')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->dropColumn('lab_fee');
            });
        }
    }
};
