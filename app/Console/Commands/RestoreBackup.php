<?php

namespace App\Console\Commands;

use App\Services\DatabaseBackupService;
use Illuminate\Console\Command;

/**
 * Puts a backup back (2026-10-13, by request): the database from its zip
 * (or an older .sql) and the uploaded files from the `uploads` folder
 * beside it, then runs migrations so an older backup fits this version.
 * Backs up the current state first, so a wrong choice can be undone.
 * Used by the offline control panel's "Restore" button.
 */
class RestoreBackup extends Command
{
    protected $signature = 'backup:restore {file : A backup file name in the backups folder, or a full path} {--force : Do not ask for confirmation}';

    protected $description = 'Replace the database and uploaded files with a backup.';

    public function handle(DatabaseBackupService $backups): int
    {
        $file = $this->argument('file');
        $path = is_file($file) ? realpath($file) : $backups->fullPath($file);

        if (! $path) {
            $this->error("Backup not found: {$file}");

            return self::FAILURE;
        }

        if (! $this->option('force') && ! $this->confirm("Replace all current data with {$path}?")) {
            return self::FAILURE;
        }

        $safety = $backups->create('before-restore');
        $this->info("Current data saved first: {$safety['filename']}");

        try {
            $backups->restore($path);
        } catch (\Throwable $e) {
            // Tables were already dropped: put the data from just before back.
            $backups->restore($backups->fullPath($safety['filename']));
            $this->call('migrate', ['--force' => true]);
            $this->warn("The previous data was put back from {$safety['filename']}.");
            // Last, so the panel (which shows the last lines) shows why.
            $this->error('Restore failed: '.$e->getMessage());

            return self::FAILURE;
        }
        $this->call('migrate', ['--force' => true]);
        $this->call('cache:clear');

        $this->info("Restored: {$path}");

        return self::SUCCESS;
    }
}
