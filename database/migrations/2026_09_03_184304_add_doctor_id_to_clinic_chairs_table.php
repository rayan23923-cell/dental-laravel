<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    /**
     * Individual-doctor seating (2026-09-04, by request — "كل كرسي لاسم
     * طبيب معين"): a chair can now point at one specific `Doctor`, not
     * just a `Group` as a whole. `group_id` stays set alongside
     * `doctor_id` when a chair is assigned this way (which group a
     * doctor's chair came from is worth keeping even if their own group
     * membership changes later), so both columns are read together, not
     * exclusively — see `ClinicChairController::assignGroup()`. Plain
     * `integer`, no DB-level FK, matching `group_id` on this same table
     * and every other column pointing at a legacy-imported table.
     */
    public function up(): void
    {
        Schema::table('clinic_chairs', function (Blueprint $table) {
            $table->integer('doctor_id')->nullable()->after('group_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('clinic_chairs', function (Blueprint $table) {
            $table->dropColumn('doctor_id');
        });
    }
};
