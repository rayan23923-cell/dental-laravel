<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// One licensing portal for two offline systems (2026-11-05, by request): the
// clinic system and FileNest (files and library). Every code is for one of them.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('offline_licenses', function (Blueprint $table) {
            $table->string('product', 20)->default('dental')->after('code')->index();
        });
    }

    public function down(): void
    {
        Schema::table('offline_licenses', function (Blueprint $table) {
            $table->dropIndex(['product']);
            $table->dropColumn('product');
        });
    }
};
