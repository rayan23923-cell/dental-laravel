<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * FCM device tokens, one row per installed app instance — `tokenable` is
 * polymorphic (Doctor or User) so both account types can register. Used by
 * `App\Services\PushNotifier` to know which devices to send a push to for a
 * given notifiable; empty/unused until a real Firebase project exists.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_tokens', function (Blueprint $table) {
            $table->id();
            $table->morphs('tokenable');
            $table->string('token')->unique();
            $table->string('platform')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
