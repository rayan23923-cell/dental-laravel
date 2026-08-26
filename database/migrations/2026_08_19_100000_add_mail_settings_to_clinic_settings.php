<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * SMTP settings on the clinic_settings row.
 *
 * The original app has **no mail configuration and sends no mail at all** —
 * its `enable_email` column is a flag nothing ever reads (verified by
 * grepping the whole codebase for `mail(`/PHPMailer/SMTP: only
 * settings_helper.php's own getter matches). Forgot-password and email
 * notifications are therefore new features here, and they need somewhere to
 * put credentials; keeping them on the same single-row settings record
 * matches how the rest of the clinic configuration is stored, rather than
 * forcing a .env edit to change the mail host.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->string('mail_host')->nullable();
            $table->unsignedInteger('mail_port')->nullable();
            $table->string('mail_username')->nullable();
            $table->text('mail_password')->nullable();
            $table->string('mail_encryption', 10)->nullable();
            $table->string('mail_from_address')->nullable();
            $table->string('mail_from_name')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn([
                'mail_host', 'mail_port', 'mail_username', 'mail_password',
                'mail_encryption', 'mail_from_address', 'mail_from_name',
            ]);
        });
    }
};
