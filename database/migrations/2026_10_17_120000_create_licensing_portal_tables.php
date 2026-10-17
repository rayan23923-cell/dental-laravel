<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// The licensing portal (2026-10-17, by request): its own site and accounts
// for managing universities, their activation codes, and the computers using
// them with the offline build each one has installed.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('license_admins', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('username')->unique();
            $table->string('password');
            $table->rememberToken();
            $table->timestamp('last_login_at')->nullable();
            $table->timestamps();
        });

        Schema::create('license_universities', function (Blueprint $table) {
            $table->id();
            $table->string('name')->unique();
            $table->string('contact')->nullable();
            $table->string('notes')->nullable();
            $table->timestamps();
        });

        Schema::table('offline_licenses', function (Blueprint $table) {
            $table->foreignId('university_id')->nullable()->after('university');
            $table->unsignedInteger('installed_build')->nullable()->after('last_seen_at');
            $table->string('last_ip', 45)->nullable()->after('installed_build');
        });

        // Codes made before the portal name their university as text only.
        foreach (DB::table('offline_licenses')->distinct()->pluck('university') as $name) {
            $id = DB::table('license_universities')->insertGetId(['name' => $name, 'created_at' => now(), 'updated_at' => now()]);
            DB::table('offline_licenses')->where('university', $name)->update(['university_id' => $id]);
        }
    }

    public function down(): void
    {
        Schema::table('offline_licenses', function (Blueprint $table) {
            $table->dropColumn(['university_id', 'installed_build', 'last_ip']);
        });
        Schema::dropIfExists('license_universities');
        Schema::dropIfExists('license_admins');
    }
};
