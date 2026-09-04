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
     * Per-user language preference (2026-09-04, by request — "اضف اللغة
     * العربية والإنجليزية ... حسب لغة النظام او حسب اختيار المستخدم").
     * `null` means "follow the browser/system language" rather than a
     * fixed choice — see `App\Http\Middleware\ResolveLocale`.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('locale', 5)->nullable()->after('email');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('locale');
        });
    }
};
