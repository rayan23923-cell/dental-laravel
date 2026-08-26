<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Daily-backup toggle + last-run timestamp for App\Services\DatabaseBackupService.
 *
 * The original (admin/ajax/backup_db.php) tried to persist the equivalent
 * of these two values in a table it also calls `clinic_settings`, but with
 * a completely different, key/value shape (`setting_key`/`setting_value`,
 * created via its own `CREATE TABLE IF NOT EXISTS`). The real
 * `clinic_settings` table (confirmed via `information_schema` on the
 * imported `clinic_system2` database) is the single-row profile shape this
 * app already ports — no `setting_key` column at all — so that `CREATE
 * TABLE IF NOT EXISTS` was always a no-op against the existing table, and
 * every `INSERT ... (setting_key, setting_value)` after it threw an
 * "unknown column" error the code silently swallows. In the original,
 * `enable_daily_backup` and `last_backup_at` were therefore never actually
 * saved — the toggle always reloaded unchecked and "last backup" always
 * showed "لا يوجد نسخ سابق" regardless of real history. Not reproduced
 * here: these two columns are added directly to the real single-row
 * settings table instead, which already holds every other clinic-wide
 * flag (`enable_notifications`, `enable_sms`, …).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->boolean('enable_daily_backup')->default(false);
            $table->timestamp('last_backup_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('clinic_settings', function (Blueprint $table) {
            $table->dropColumn(['enable_daily_backup', 'last_backup_at']);
        });
    }
};
