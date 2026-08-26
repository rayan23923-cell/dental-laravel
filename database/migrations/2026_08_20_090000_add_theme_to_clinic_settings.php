<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * App-wide UI theme, picked from the settings page.
 *
 * Stored on `clinic_settings` rather than per user because that is where
 * every other appearance setting already lives (clinic name, logos,
 * university branding) and because a teaching clinic's screens are shared —
 * the same workstation is used by whoever is on shift.
 *
 * Defaults to the palette of the dental-unit control panel this design is
 * modelled on (dark slate + mint), see App\Support\ThemePalette.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->string('theme', 40)->default('unit-dark')->after('clinic_currency');
        });
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn('theme');
        });
    }
};
