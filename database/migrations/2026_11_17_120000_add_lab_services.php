<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Lab services (2026-11-17, by request): the lab adds its own priced
 * services, such as «فحص المختبر» for 2,000, and registers a patient who
 * came for the test only. Only the lab sees them: they are not offered on
 * the reception form, and such a patient stays off the reception list.
 * The fee is booked as a lab payment («مدفوعات المختبر») when the result
 * is recorded, like the clinic's lab fee.
 */
return new class extends Migration
{
    private const GRANTS = ['view', 'manage', 'register'];

    public function up(): void
    {
        Schema::create('lab_services', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100);
            $table->decimal('price', 12, 2)->default(0);
            $table->boolean('active')->default(true);
            $table->unsignedInteger('sort')->default(0);
            $table->unsignedBigInteger('created_by')->nullable();
            $table->timestamps();
        });

        Schema::table('patients_simple', function (Blueprint $table) {
            $table->unsignedBigInteger('lab_service_id')->nullable()->index();
        });

        // Lab accounts that already exist get the new grants, like new ones
        // do through App\Support\RolePresets.
        foreach (DB::table('users')->where('role', 'lab')->pluck('id') as $userId) {
            foreach (self::GRANTS as $permission) {
                DB::table('user_permissions')->updateOrInsert(
                    ['user_id' => $userId, 'module' => 'lab_services', 'permission' => $permission],
                    ['granted' => 1, 'created_at' => now()],
                );
            }
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'lab_services')->delete();

        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropIndex(['lab_service_id']);
            $table->dropColumn('lab_service_id');
        });

        Schema::dropIfExists('lab_services');
    }
};
