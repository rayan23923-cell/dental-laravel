<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * `patients_simple` (the reception-desk "register a new patient with a
 * service + day" table — distinct from `patients`, the doctor/task/stage
 * tracking table `App\Models\Patient` already covers) has sat in the
 * imported schema unused since the schema import, alongside
 * `register_days`/`register_services`/`register_day_service_map`. The
 * legacy app never stored the chosen service as a real foreign key at
 * all — it concatenated it into the free-text `note` column
 * (`'نوع الخدمة: ' . $service . ' - ' . $note`) and stored `day` as
 * *either* the day's Arabic name or its numeric id depending on which of
 * its two entry points was used (`patient_register.php` vs
 * `public_register.php`) — confirmed inconsistent by reading both files
 * directly. This migration does not replicate either: it adds real FKs
 * so the new registration feature has one unambiguous way to record a
 * patient's chosen service/day.
 *
 * Nullable and additive — existing rows (real historical data already in
 * this table, using the legacy `note`/`day` text columns, which are left
 * untouched) simply have no value for the new columns until re-entered.
 * No FK constraint added (`register_days`/`register_services` rows can be
 * deleted by an admin later; a hard constraint would block that for a
 * historical registration row with no good default to fall back to).
 *
 * Also relaxes `day` (imported as `varchar(50) NOT NULL`, no default) to
 * nullable — found live, via a real insert failure: new code deliberately
 * never writes to this legacy column (see above), so a NOT NULL
 * constraint on it blocked every new registration outright. Same bug
 * class already on record elsewhere in this project (columns imported
 * from `clinic_system2` with constraints that made sense for the code
 * that used to write them, not for code that doesn't).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->unsignedInteger('service_id')->nullable()->after('note');
            $table->unsignedInteger('register_day_id')->nullable()->after('service_id');
            $table->index('service_id');
            $table->index('register_day_id');
            $table->string('day', 50)->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropIndex(['service_id']);
            $table->dropIndex(['register_day_id']);
            $table->dropColumn(['service_id', 'register_day_id']);
            $table->string('day', 50)->nullable(false)->change();
        });
    }
};
