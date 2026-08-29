<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Replaces the emailed reset *link* with a short-lived numeric code
 * (2026-08-29, by request) — the original `password_reset_tokens` table
 * (Laravel's stock password-broker table, still used by nothing after this
 * change — see App\Services\OtpPasswordResetBroker) stores a long
 * URL-safe token meant to be clicked, not typed, and its 60-minute expiry
 * lives in config/auth.php rather than being enforced at the point the
 * page itself loads (see the README entry this migration ships with for
 * the full "the link still worked after a day" investigation). This table
 * is deliberately separate rather than repurposed, since both shapes
 * (long clickable token vs short typed code) need to coexist during
 * rollout and the two have different natural primary keys.
 *
 * `guard` disambiguates `users` (staff) from `doctors` — both account
 * types share this one table (mirroring how config/auth.php's two
 * password-reset brokers already shared `password_reset_tokens`), keyed
 * together with `email` so the same address can hold at most one
 * outstanding code per guard.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('password_reset_otps', function (Blueprint $table) {
            $table->string('email');
            $table->string('guard', 10);
            $table->string('otp');
            $table->timestamp('expires_at');
            $table->timestamp('created_at')->nullable();
            $table->primary(['email', 'guard']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('password_reset_otps');
    }
};
