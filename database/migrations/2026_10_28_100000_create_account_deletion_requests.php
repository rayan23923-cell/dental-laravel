<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Account deletion requests (2026-10-28, for publishing on Google Play and
 * the App Store, which both want a way to ask for an account's deletion,
 * in the app and on a public page). Accounts are made and removed by the
 * clinic's administration, so a request is recorded here and the admins
 * are notified; they delete the account from the users/doctors pages.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('account_deletion_requests')) {
            return;
        }

        Schema::create('account_deletion_requests', function (Blueprint $table) {
            $table->id();
            // Set when the request came from a signed-in account (the app).
            $table->string('account_type', 16)->nullable();
            $table->unsignedBigInteger('account_id')->nullable();
            // What the person typed on the public page, or the account's own username/email.
            $table->string('identifier', 191);
            $table->string('contact', 191)->nullable();
            $table->text('reason')->nullable();
            $table->string('source', 8);
            $table->string('status', 16)->default('pending');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('account_deletion_requests');
    }
};
