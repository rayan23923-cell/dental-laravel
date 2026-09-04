<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    /**
     * Same `locale` preference as `users` (see that migration's own doc
     * comment) — added for doctors too since the request covers "جميع
     * المستخدمين المشرفين والأطباء". No web UI to set this one yet (doctors
     * don't use the web login) — this is groundwork for a Flutter profile
     * screen follow-up; `App\Http\Middleware\ResolveLocale` already checks
     * it for the `doctor` guard regardless.
     */
    public function up(): void
    {
        Schema::table('doctors', function (Blueprint $table) {
            $table->string('locale', 5)->nullable()->after('email');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('doctors', function (Blueprint $table) {
            $table->dropColumn('locale');
        });
    }
};
