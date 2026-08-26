<?php

namespace App\Console\Commands;

use App\Models\ClinicSetting;
use App\Services\DatabaseBackupService;
use Illuminate\Console\Command;

/**
 * Scheduled counterpart to BackupController::store() — see
 * routes/console.php for the daily schedule. Skips when the admin hasn't
 * turned the toggle on, and skips again if today's backup already ran (the
 * same "already_done_today" de-dup the original's `action=auto` branch
 * has), so re-running the scheduler within the same day is harmless.
 */
class RunDatabaseBackup extends Command
{
    protected $signature = 'backup:run';

    protected $description = 'Create a database backup if daily auto-backup is enabled and none has run yet today.';

    public function handle(DatabaseBackupService $backups): int
    {
        $settings = ClinicSetting::current();

        if (! $settings->enable_daily_backup) {
            $this->info('Daily backup is disabled; skipping.');

            return self::SUCCESS;
        }

        if ($settings->last_backup_at?->isToday()) {
            $this->info('A backup already ran today; skipping.');

            return self::SUCCESS;
        }

        $result = $backups->create();
        $settings->update(['last_backup_at' => now()]);

        $this->info("Backup created: {$result['filename']}");

        return self::SUCCESS;
    }
}
