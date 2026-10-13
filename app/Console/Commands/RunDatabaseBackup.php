<?php

namespace App\Console\Commands;

use App\Models\ClinicSetting;
use App\Services\DatabaseBackupService;
use Illuminate\Console\Command;
use Illuminate\Database\Migrations\Migrator;
use Illuminate\Support\Facades\Schema;

/**
 * Scheduled counterpart to BackupController::store() — see
 * routes/console.php for the schedule. Skips when neither the admin's
 * toggle nor `backup.daily` (on in the offline package) asks for it, and
 * skips again if today's backup already ran (the same
 * "already_done_today" de-dup the original's `action=auto` branch has),
 * so running it every hour only backs up once a day, whenever the
 * computer is on.
 *
 * `--before-update` (2026-10-13): the offline control panel runs this
 * before migrating on every start, and it backs up only when there are
 * migrations to run, i.e. a new version was just put in place.
 * `--force` backs up now, whatever the settings (the panel's button).
 */
class RunDatabaseBackup extends Command
{
    protected $signature = 'backup:run {--force : Back up now} {--before-update : Back up only if there are pending migrations}';

    protected $description = 'Create a backup of the database and uploaded files (daily, before an update, or now).';

    public function handle(DatabaseBackupService $backups, Migrator $migrator): int
    {
        if ($this->option('before-update')) {
            if (! $this->hasPendingMigrations($migrator)) {
                $this->info('No update to apply; skipping.');

                return self::SUCCESS;
            }

            return $this->backup($backups, 'before-update');
        }

        if ($this->option('force')) {
            return $this->backup($backups);
        }

        $settings = ClinicSetting::current();

        if (! $settings->enable_daily_backup && ! config('backup.daily')) {
            $this->info('Daily backup is disabled; skipping.');

            return self::SUCCESS;
        }

        if ($settings->last_backup_at?->isToday()) {
            $this->info('A backup already ran today; skipping.');

            return self::SUCCESS;
        }

        return $this->backup($backups);
    }

    private function backup(DatabaseBackupService $backups, string $suffix = ''): int
    {
        $result = $backups->create($suffix);
        if (Schema::hasTable('clinic_settings')) {
            ClinicSetting::current()->update(['last_backup_at' => now()]);
        }

        $this->info("Backup created: {$backups->dir()}".DIRECTORY_SEPARATOR.$result['filename']);

        return self::SUCCESS;
    }

    /** A fresh install (no migrations table yet) has nothing to lose. */
    private function hasPendingMigrations(Migrator $migrator): bool
    {
        if (! $migrator->repositoryExists()) {
            return false;
        }

        $files = $migrator->getMigrationFiles(array_merge([database_path('migrations')], $migrator->paths()));

        return array_diff(array_keys($files), $migrator->getRepository()->getRan()) !== [];
    }
}
