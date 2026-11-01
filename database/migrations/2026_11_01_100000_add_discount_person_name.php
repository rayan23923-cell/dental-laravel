<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Student / employee discount (2026-11-01, by request): the registration
 * also records the student's or employee's name (with the stage, or the
 * workplace), since the eligible person is not always the patient.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('patients_simple', 'discount_person_name')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->string('discount_person_name', 255)->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('patients_simple', 'discount_person_name')) {
            Schema::table('patients_simple', fn (Blueprint $t) => $t->dropColumn('discount_person_name'));
        }
    }
};
