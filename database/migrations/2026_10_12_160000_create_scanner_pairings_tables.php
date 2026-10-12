<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Phone as a QR scanner for a computer (2026-10-12, by request). A staff
 * member's computer opens a pairing; a phone joins it by scanning its QR
 * (which carries `token`) or typing its six-digit `code`, then every code
 * the phone's camera reads is stored in `scanner_scans` and picked up by
 * that computer. See App\Models\ScannerPairing.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('scanner_pairings', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id')->index();
            $table->string('token', 64)->unique();
            $table->string('code', 6)->index();
            $table->timestamp('phone_joined_at')->nullable();
            $table->timestamp('expires_at')->index();
            $table->timestamps();
        });

        Schema::create('scanner_scans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('scanner_pairing_id')->constrained('scanner_pairings')->cascadeOnDelete();
            $table->text('payload');
            $table->timestamp('created_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('scanner_scans');
        Schema::dropIfExists('scanner_pairings');
    }
};
