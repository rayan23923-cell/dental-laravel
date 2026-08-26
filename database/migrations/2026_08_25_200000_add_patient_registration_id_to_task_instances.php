<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links a task instance to the specific patient registration it was
 * started for — previously `task_instances` was purely a (task, doctor)
 * case-count assignment with no patient identity at all. Nullable for
 * historical rows created before this column existed; every new
 * `TaskStarter::start()` call stamps it going forward (required at the
 * validation layer, not the DB layer — same "additive link, no FK"
 * convention as `payments.patient_registration_id`).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->integer('patient_registration_id')->nullable()->after('doctor_id')->index();
        });
    }

    public function down(): void
    {
        Schema::table('task_instances', function (Blueprint $table) {
            $table->dropColumn('patient_registration_id');
        });
    }
};
