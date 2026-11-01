<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Care codes, "بطاقات الرعاية" (2026-11-01, by request): one-time 5-digit
 * codes, printed as cards and handed out, that make a patient's service and
 * lab test free. Off until switched on in the registration settings. See
 * App\Support\SupportCodes.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('support_codes')) {
            Schema::create('support_codes', function (Blueprint $table) {
                $table->id();
                $table->string('code', 5)->unique();
                // The generation it came from, so a printed batch can be found and stopped together.
                $table->unsignedInteger('batch')->index();
                $table->string('note', 255)->nullable();
                $table->unsignedBigInteger('created_by')->nullable();
                $table->timestamp('disabled_at')->nullable();
                $table->unsignedBigInteger('disabled_by')->nullable();
                $table->timestamp('used_at')->nullable();
                $table->unsignedBigInteger('patient_registration_id')->nullable()->index();
                $table->string('used_by', 255)->nullable();
                // What was not charged, at the prices of that day.
                $table->decimal('waived_service', 12, 2)->nullable();
                $table->decimal('waived_lab', 12, 2)->nullable();
                $table->timestamps();
            });
        }

        if (! Schema::hasColumn('patients_simple', 'support_code_id')) {
            Schema::table('patients_simple', function (Blueprint $table) {
                $table->unsignedBigInteger('support_code_id')->nullable()->index();
            });
        }

        if (! Schema::hasColumn('clinic_settings', 'support_codes_enabled')) {
            Schema::table('clinic_settings', function (Blueprint $table) {
                $table->boolean('support_codes_enabled')->default(false);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('support_codes');
        if (Schema::hasColumn('patients_simple', 'support_code_id')) {
            Schema::table('patients_simple', fn (Blueprint $t) => $t->dropColumn('support_code_id'));
        }
        if (Schema::hasColumn('clinic_settings', 'support_codes_enabled')) {
            Schema::table('clinic_settings', fn (Blueprint $t) => $t->dropColumn('support_codes_enabled'));
        }
    }
};
