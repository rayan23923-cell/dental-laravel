<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links a doctor account to a physical NFC tag's hardware UID (uppercase
 * hex, no separators) — not custom-written NDEF data, so read-only/factory
 * tags work and there's no provisioning step beyond "tap once to link" from
 * the Flutter app (browsers can't read NFC, so this is scanned client-side
 * only; the field itself stays a plain editable text field on the web
 * doctor form for manual correction). No precedent in the legacy app —
 * confirmed via a dedicated grep of dental_clinics2 before building this;
 * every "بطاقة" ("card") hit there was the unrelated printable ID-card
 * feature, no scannable identifier.
 *
 * Nullable + unique, same shape as every other optional identifier column
 * in this codebase.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('doctors', function (Blueprint $table) {
            $table->string('nfc_tag_id', 64)->nullable()->unique()->after('profile_image');
        });
    }

    public function down(): void
    {
        Schema::table('doctors', function (Blueprint $table) {
            $table->dropUnique(['nfc_tag_id']);
            $table->dropColumn('nfc_tag_id');
        });
    }
};
