<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "طلبات بدء المهام" (2026-10-14, by request): a doctor asks for a task to
 * be started, with either the electronic case sheet (their pre-instance
 * draft) or a photo of the paper one; staff with task-progress rights
 * review it and start the task. See App\Services\TaskStartRequests.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('task_start_requests', function (Blueprint $table) {
            $table->id();
            // doctors.id / tasks.id / task_instances.id are the legacy
            // schema's signed int(11); no FKs, like the other *_by columns.
            $table->integer('doctor_id')->index();
            $table->integer('task_id')->index();
            $table->string('form_type', 20); // electronic | paper
            $table->string('photo_path')->nullable();
            $table->text('notes')->nullable();
            $table->string('status', 20)->default('pending')->index(); // pending | approved | rejected
            $table->unsignedBigInteger('reviewed_by_user_id')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->text('review_note')->nullable();
            $table->integer('task_instance_id')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('task_start_requests');
    }
};
