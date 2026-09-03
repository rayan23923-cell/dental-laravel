<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Physical chair layout for the "know where every group/doctor
        // sits" clinic map (2026-09-03, by request — "اماكن كراسي الاسنان
        // ... وكل مجموعة لها اماكن معينة ... تكون مرتبه بشكل خطوط مستقيمة
        // واحد بصف الاخر"). A chair is assigned to a *group*, not an
        // individual doctor — a group's own roster (`doctor_group_members`)
        // already answers "which doctors", so pinning a whole group to a
        // chair is what actually answers "where in the clinic". One group
        // can hold several chairs (`group_id` isn't unique).
        Schema::create('clinic_chairs', function (Blueprint $table) {
            $table->id();
            // Straight rows, one after another — `row_number`/`column_number`
            // are the only layout state; drag-and-drop reordering just
            // rewrites these two columns (see ClinicChairController::reorder()).
            $table->unsignedInteger('row_number');
            $table->unsignedInteger('column_number');
            // Plain `integer`, no DB-level FK constraint — `groups.id` is a
            // legacy `int(11)` from `database/schema_import.sql`, not a
            // Laravel `bigIncrements`, and nothing else in this codebase
            // constrains a column against it either (see the
            // `2026_08_27_090000` migration's own doc comment); referential
            // integrity here is Eloquent's, same as every other *_id column
            // pointing at a legacy-imported table.
            $table->integer('group_id')->nullable();
            $table->string('label')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('clinic_chairs');
    }
};
