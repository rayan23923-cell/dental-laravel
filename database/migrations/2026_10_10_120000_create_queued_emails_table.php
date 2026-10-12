<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Outgoing mail that has to respect a daily sending cap (Gmail SMTP allows
 * roughly 500 messages a day), e.g. the welcome email with login details for
 * every account an Excel import creates. `mail:send-queued` drains it.
 *
 * `payload` is encrypted at rest (it holds the generated password) and is
 * wiped as soon as the message is sent.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('queued_emails', function (Blueprint $table) {
            $table->id();
            $table->string('kind', 50);
            $table->string('recipient_email');
            $table->string('recipient_name')->nullable();
            $table->text('payload')->nullable();
            $table->string('status', 20)->default('pending');
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->text('last_error')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->timestamps();

            $table->index(['status', 'id']);
            $table->index('sent_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('queued_emails');
    }
};
