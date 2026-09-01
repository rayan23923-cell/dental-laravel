<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('personal_access_tokens', function (Blueprint $table) {
            // Captured once at login (App\Http\Controllers\Api\AuthController::login())
            // rather than re-resolved on every "list my sessions" read — an
            // Instagram-style "Active sessions" screen only needs to show
            // where/what a session was created from, not live-tracked
            // location, and caching here avoids an external geolocation
            // call on a hot read path.
            $table->string('ip_address')->nullable()->after('name');
            $table->string('location')->nullable()->after('ip_address');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('personal_access_tokens', function (Blueprint $table) {
            $table->dropColumn(['ip_address', 'location']);
        });
    }
};
