<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Photos of a task's paper case sheet (2026-10-13, by request). Staff
 * attach them from the computer, or ask the paired phone for one: the
 * phone's scanner page shows the request, the photo it takes is stored as
 * a `scanner_scans` row with `photo_path`, and the computer attaches it.
 * See App\Models\TaskInstanceAttachment and App\Models\ScannerPairing.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('task_instance_attachments', function (Blueprint $table) {
            $table->id();
            // task_instances.id is the legacy schema's signed int(11).
            $table->integer('task_instance_id');
            $table->foreign('task_instance_id')->references('id')->on('task_instances')->cascadeOnDelete();
            $table->string('path');
            $table->unsignedInteger('size')->default(0);
            // Staff (users) or the student (doctors) who added it; no FK,
            // like the other *_by columns on task_instances.
            $table->unsignedBigInteger('uploaded_by_user_id')->nullable();
            $table->unsignedBigInteger('uploaded_by_doctor_id')->nullable();
            $table->timestamp('created_at')->nullable();
        });

        Schema::table('scanner_scans', function (Blueprint $table) {
            $table->string('photo_path')->nullable()->after('payload');
        });

        Schema::table('scanner_pairings', function (Blueprint $table) {
            $table->string('photo_request')->nullable()->after('phone_joined_at');
        });
    }

    public function down(): void
    {
        Schema::table('scanner_pairings', fn (Blueprint $table) => $table->dropColumn('photo_request'));
        Schema::table('scanner_scans', fn (Blueprint $table) => $table->dropColumn('photo_path'));
        Schema::dropIfExists('task_instance_attachments');
    }
};
