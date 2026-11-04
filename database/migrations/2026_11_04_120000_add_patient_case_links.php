<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Linking a patient to a case sheet by QR or typed code (2026-11-04, by
 * request), see App\Support\CasePatientLinks:
 * - `patients_simple.patient_code`: a 6-digit code printed under the
 *   ticket/receipt QR, typed when the camera can't be used.
 * - `case_patient_links`: which case (doctor + task, or a started task
 *   instance) a registration went to. One registration, one case, so a
 *   receipt can't be used for more than one patient.
 * - `clinic_settings.patient_link_required`: linking optional (default)
 *   or required before a case sheet is saved.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->string('patient_code', 10)->nullable()->unique();
        });

        $used = [];
        DB::table('patients_simple')->whereNull('patient_code')->orderBy('id')->select('id')
            ->chunkById(500, function ($rows) use (&$used) {
                foreach ($rows as $row) {
                    do {
                        $code = (string) random_int(100000, 999999);
                    } while (isset($used[$code]));
                    $used[$code] = true;
                    DB::table('patients_simple')->where('id', $row->id)->update(['patient_code' => $code]);
                }
            });

        Schema::create('case_patient_links', function (Blueprint $table) {
            $table->id();
            // Nullable only so a permanent delete of the registration can
            // clear it (App\Support\RegistrationArchive); unique = one case.
            $table->unsignedBigInteger('patient_registration_id')->nullable()->unique();
            $table->unsignedBigInteger('doctor_id')->nullable()->index();
            $table->unsignedBigInteger('task_id')->nullable()->index();
            $table->unsignedBigInteger('task_instance_id')->nullable()->index();
            $table->unsignedBigInteger('department_id')->nullable()->index();
            // 'qr' or 'code': how the doctor entered it.
            $table->string('method', 10)->nullable();
            $table->timestamps();
        });

        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->boolean('patient_link_required')->default(false);
        });

        // Patients a supervisor already started a task for (scanned QR).
        $instances = DB::table('task_instances')
            ->join('tasks', 'tasks.id', '=', 'task_instances.task_id')
            ->whereNotNull('task_instances.patient_registration_id')
            ->orderBy('task_instances.id')
            ->get(['task_instances.id', 'task_instances.patient_registration_id', 'task_instances.doctor_id', 'task_instances.task_id', 'tasks.department_id']);
        $seen = [];
        foreach ($instances as $instance) {
            if (isset($seen[$instance->patient_registration_id])) {
                continue;
            }
            $seen[$instance->patient_registration_id] = true;
            DB::table('case_patient_links')->insert([
                'patient_registration_id' => $instance->patient_registration_id,
                'doctor_id' => $instance->doctor_id,
                'task_id' => $instance->task_id,
                'task_instance_id' => $instance->id,
                'department_id' => $instance->department_id,
                'method' => 'qr',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn('patient_link_required');
        });
        Schema::dropIfExists('case_patient_links');
        Schema::table('patients_simple', function (Blueprint $table) {
            $table->dropUnique(['patient_code']);
            $table->dropColumn('patient_code');
        });
    }
};
