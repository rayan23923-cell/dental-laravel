<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The supervisor's note on a photo a doctor attached to a case (2026-10-15,
 * by request: "المشرف معاينة الصورة وتدوين الملاحظات").
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('task_instance_attachments', function (Blueprint $table) {
            $table->text('note')->nullable()->after('size');
            $table->unsignedBigInteger('note_by_user_id')->nullable()->after('note');
            $table->timestamp('note_at')->nullable()->after('note_by_user_id');
        });
    }

    public function down(): void
    {
        Schema::table('task_instance_attachments', function (Blueprint $table) {
            $table->dropColumn(['note', 'note_by_user_id', 'note_at']);
        });
    }
};
