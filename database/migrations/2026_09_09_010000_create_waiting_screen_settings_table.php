<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Single-row settings table (always id=1) for the public waiting-room
 * appointments display (`/waiting-screen`), same "always id=1" convention
 * as `clinic_settings` (see `App\Models\ClinicSetting::current()`).
 *
 * `stage_id`/`group_id` are plain nullable ints with no FK, same reasoning
 * as `appointments.patient_registration_id`/`case_sheet_doctor_id`: this
 * is a display filter, not a relational integrity concern, and a stage or
 * group being deleted later shouldn't be blocked by this settings row.
 * Both null means "show every doctor's appointments, unfiltered."
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('waiting_screen_settings', function (Blueprint $table) {
            $table->unsignedTinyInteger('id')->primary();
            $table->integer('stage_id')->nullable();
            $table->integer('group_id')->nullable();
            $table->unsignedSmallInteger('patients_per_page')->default(8);
            $table->unsignedSmallInteger('rotation_seconds')->default(12);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('waiting_screen_settings');
    }
};
