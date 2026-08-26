<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links appointments to reception-desk registrations ("المرضى المسجلين",
 * `patients_simple`) instead of the plain `patients` table — mirrors
 * `2026_08_22_090000_add_patient_registration_to_payments.php`'s exact
 * shape and reasoning.
 *
 * `patients_simple` has no relation to `patients` at all (confirmed via
 * `PatientRegistration`'s own docblock — deliberately separate identities),
 * so existing appointments' `patient_id` values can't be migrated to the
 * new column; they simply keep pointing at their existing `patients` row.
 * `patient_id` becomes nullable so *new* appointments (which will only
 * ever be created via a registered patient going forward) don't need one.
 * No FK constraint on the new column, same reasoning as the payments
 * migration: a registration could be deleted later without cascading into
 * a historical appointment.
 *
 * A real bug found live while writing this: `patients.id` is a plain
 * signed `int(11)` (this legacy schema's auto-increment PK convention),
 * not unsigned — using `unsignedInteger('patient_id')` here (an easy
 * default reach) makes the type mismatch the FK re-add step, MySQL
 * errno 150 ("Foreign key constraint is incorrectly formed"). Confirmed
 * by reading `patients.id`'s actual column type directly rather than
 * guessing; `integer()` (signed) is correct here.
 */
return new class extends Migration
{
    public function up(): void
    {
        // MySQL refuses to change a column's nullability while it's part
        // of an active FK constraint ("Cannot change column 'patient_id':
        // used in a foreign key constraint 'appointments_ibfk_1'") —
        // confirmed live, not assumed. Drop the legacy-named constraint
        // (from the original raw-SQL import, not Laravel's naming
        // convention), relax the column, then re-add the same FK — NULL
        // values are simply exempt from FK checking, so existing non-null
        // rows keep exactly the same integrity guarantee as before.
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropForeign('appointments_ibfk_1');
        });

        Schema::table('appointments', function (Blueprint $table) {
            $table->integer('patient_id')->nullable()->change();
            $table->integer('patient_registration_id')->nullable()->after('patient_id');
            $table->index('patient_registration_id');
        });

        Schema::table('appointments', function (Blueprint $table) {
            $table->foreign('patient_id')->references('id')->on('patients')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropForeign(['patient_id']);
            $table->dropIndex(['patient_registration_id']);
            $table->dropColumn('patient_registration_id');
        });

        Schema::table('appointments', function (Blueprint $table) {
            $table->integer('patient_id')->nullable(false)->change();
        });

        Schema::table('appointments', function (Blueprint $table) {
            $table->foreign('patient_id')->references('id')->on('patients')->cascadeOnDelete();
        });
    }
};
