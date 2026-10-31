<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Online access to an offline server (2026-10-31, by request): its control
// panel opens a Cloudflare tunnel and reports the tunnel's address here, so
// /go/{tunnel_slug} on the hosting always leads to it even though a free
// tunnel gets a new address every time it starts.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('offline_licenses', function (Blueprint $table) {
            $table->string('tunnel_slug', 24)->nullable()->unique();
            $table->string('tunnel_url')->nullable();
            $table->string('tunnel_panel_url')->nullable();
            $table->timestamp('tunnel_seen_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('offline_licenses', function (Blueprint $table) {
            $table->dropUnique(['tunnel_slug']);
            $table->dropColumn(['tunnel_slug', 'tunnel_url', 'tunnel_panel_url', 'tunnel_seen_at']);
        });
    }
};
