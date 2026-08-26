<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a payment belong to a reception-desk registration
 * (`patients_simple` / `App\Models\PatientRegistration`) instead of only
 * to an appointment.
 *
 * The imported schema has `payments.appointment_id` as `int NOT NULL` —
 * a payment is always against an `appointments` row, and `appointments`
 * is an entirely separate concept from `patients_simple` (no FK, no
 * shared column; confirmed by reading both table definitions in
 * database/schema_import.sql). That makes the desk flow this migration
 * exists for — register a patient, print their ticket, scan its QR at
 * the payment desk, take payment — impossible to record at all today.
 *
 * Additive, exactly like the Phase 4C migration that added
 * `service_id`/`register_day_id` to `patients_simple`: the new column is
 * nullable, and `appointment_id` is relaxed to nullable so a payment can
 * carry one *or* the other. Existing appointment-based payments are
 * untouched and keep working; `Api\PaymentController::validatePayment()`
 * enforces "exactly one of the two" at the application layer, since the
 * database can't express that constraint portably here.
 *
 * No FK constraints, same reasoning as the Phase 4C migration: an admin
 * can delete a service/day/registration later, and a historical payment
 * row has no sensible fallback value to be rewritten to.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->unsignedInteger('patient_registration_id')->nullable()->after('appointment_id');
            $table->index('patient_registration_id');
            $table->unsignedInteger('appointment_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->dropIndex(['patient_registration_id']);
            $table->dropColumn('patient_registration_id');
            $table->unsignedInteger('appointment_id')->nullable(false)->change();
        });
    }
};
