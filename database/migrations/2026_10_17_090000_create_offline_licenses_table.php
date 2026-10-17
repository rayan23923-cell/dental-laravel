<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Activation codes for the offline edition (2026-10-17, by request): one per
// university copy, used once and then tied to the computer that used it.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('offline_licenses', function (Blueprint $table) {
            $table->id();
            $table->string('code', 32)->unique();
            $table->string('university');
            $table->string('notes')->nullable();
            $table->string('machine_id', 32)->nullable();
            $table->string('machine_name')->nullable();
            $table->timestamp('activated_at')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->foreignId('created_by')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('offline_licenses');
    }
};
