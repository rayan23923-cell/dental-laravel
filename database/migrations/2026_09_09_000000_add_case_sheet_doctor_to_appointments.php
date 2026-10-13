<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "الطبيب المعالج" — the doctor actually treating the patient's case sheet
 * (`doctors.id`, via the matching `task_instances` row), as opposed to
 * `appointments.doctor_id` which references `users.id` (the staff member
 * who booked/manages the appointment — see Appointment::doctor()'s own
 * docblock). Kept as a plain nullable column with no FK, same reasoning
 * as `patient_registration_id` on this same table: it's refreshed
 * whenever `App\Services\AppointmentPatientSync` runs (on appointment
 * save, and whenever `TaskStarter::start()` assigns a doctor to the
 * patient for a task) rather than being a hard relational constraint, so
 * a doctor row disappearing later shouldn't cascade into a historical
 * appointment.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->integer('case_sheet_doctor_id')->nullable()->after('doctor_id');
            $table->index('case_sheet_doctor_id');
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropIndex(['case_sheet_doctor_id']);
            $table->dropColumn('case_sheet_doctor_id');
        });
    }
};
