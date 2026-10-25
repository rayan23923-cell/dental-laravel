<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Student discount (2026-10-25, by request): a patient who is a student
 * pays a percentage less for the service and the lab test. Each service
 * has its own percentage (default 50), the lab fee has one in clinic
 * settings (default 50), and the registration records whether the patient
 * is eligible (default not eligible). See App\Support\StudentDiscount.
 *
 * Employees are eligible too (2026-10-25, by request): an eligible
 * registration is a student (with an optional stage) or an employee (with
 * an optional workplace), at the same percentages.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('register_services', 'student_discount_percent')) {
            Schema::table('register_services', function (Blueprint $table) {
                $table->decimal('student_discount_percent', 5, 2)->default(50);
            });
        }

        if (! Schema::hasColumn('clinic_settings', 'lab_student_discount_percent')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->decimal('lab_student_discount_percent', 5, 2)->nullable()->default(50);
            });
        }

        if (! Schema::hasColumn('patients_simple', 'discount_eligible')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->boolean('discount_eligible')->default(false);
            });
        }

        if (! Schema::hasColumn('patients_simple', 'discount_type')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->string('discount_type', 20)->nullable();
                $table->string('discount_stage', 100)->nullable();
                $table->string('discount_workplace', 255)->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach ([
            ['register_services', 'student_discount_percent'],
            ['clinic_settings', 'lab_student_discount_percent'],
            ['patients_simple', 'discount_eligible'],
            ['patients_simple', 'discount_type'],
            ['patients_simple', 'discount_stage'],
            ['patients_simple', 'discount_workplace'],
        ] as [$table, $column]) {
            if (Schema::hasColumn($table, $column)) {
                Schema::table($table, fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
