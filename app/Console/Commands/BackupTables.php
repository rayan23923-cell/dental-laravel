<?php

namespace App\Console\Commands;

use App\Services\DatabaseBackupService;
use Illuminate\Console\Command;

/**
 * Lists the sections (tables) a backup holds, as JSON (2026-10-20), so the
 * offline control panel can let the user choose what to take from it
 * before `backup:restore --merge`.
 */
class BackupTables extends Command
{
    protected $signature = 'backup:tables {file : A backup file name in the backups folder, or a full path}';

    protected $description = 'List the tables in a backup, as JSON.';

    public function handle(DatabaseBackupService $backups): int
    {
        $file = $this->argument('file');
        $path = is_file($file) ? realpath($file) : $backups->fullPath($file);
        if (! $path) {
            $this->error("Backup not found: {$file}");

            return self::FAILURE;
        }

        $this->line(json_encode($backups->tablesIn($path), JSON_UNESCAPED_UNICODE));

        return self::SUCCESS;
    }
}
