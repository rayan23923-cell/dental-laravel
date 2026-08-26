<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Ports admin/ajax/backup_db.php's `create_backup()` — mysqldump first,
 * falling back to a PHP-driven dump when `mysqldump` isn't reachable
 * (matches the original's own two-candidate-paths-then-PHP-fallback
 * strategy, minus the MikroTik SCP upload step, which is out of scope by
 * request — see App\Models\ClinicSetting docblock).
 *
 * Files live on the `local` disk under `backups/` (storage/app/private/
 * backups — Laravel 11+'s default `local` root, not the `public` disk, so
 * it isn't reachable through the `public/storage` symlink at all) — a
 * narrower door than the original's `admin/downloads/backups/`, a plain
 * folder inside the public web root. Downloading goes through
 * BackupController::download, behind the same admin-only route gate as
 * everything else here.
 */
class DatabaseBackupService
{
    private const DISK = 'local';

    private const DIR = 'backups';

    public function create(): array
    {
        $connection = config('database.connections.'.config('database.default'));
        $database = $connection['database'];
        $timestamp = now()->format('Ymd_His');
        $filename = "{$database}_{$timestamp}.sql";

        Storage::disk(self::DISK)->makeDirectory(self::DIR);
        $fullPath = Storage::disk(self::DISK)->path(self::DIR.DIRECTORY_SEPARATOR.$filename);

        if (! $this->dumpWithMysqldump($connection, $fullPath)) {
            $this->dumpWithPhp($fullPath);
        }

        return [
            'filename' => $filename,
            'size' => Storage::disk(self::DISK)->size(self::DIR.'/'.$filename),
        ];
    }

    /** @return array<int, array{name: string, size: int, mtime: int}> */
    public function list(): array
    {
        if (! Storage::disk(self::DISK)->exists(self::DIR)) {
            return [];
        }

        $files = collect(Storage::disk(self::DISK)->files(self::DIR))
            ->filter(fn ($path) => str_ends_with($path, '.sql'))
            ->map(fn ($path) => [
                'name' => basename($path),
                'size' => Storage::disk(self::DISK)->size($path),
                'mtime' => Storage::disk(self::DISK)->lastModified($path),
            ])
            ->sortByDesc('mtime')
            ->values();

        // The original caps its list at 10 most-recent files; kept for
        // parity (the download links stay valid for older files on disk,
        // this only limits what the status list shows).
        return $files->take(10)->all();
    }

    public function fullPath(string $filename): ?string
    {
        // Reject anything that isn't a bare filename before it ever touches
        // the filesystem — path separators or `..` would let a crafted
        // download request escape the backups directory.
        if ($filename !== basename($filename) || ! str_ends_with($filename, '.sql')) {
            return null;
        }

        $relative = self::DIR.'/'.$filename;

        return Storage::disk(self::DISK)->exists($relative)
            ? Storage::disk(self::DISK)->path($relative)
            : null;
    }

    /** Tries the bundled XAMPP mysqldump, then whatever `mysqldump` resolves to on PATH. */
    private function dumpWithMysqldump(array $connection, string $fullPath): bool
    {
        $candidates = ['C:\\xampp\\mysql\\bin\\mysqldump.exe', 'mysqldump'];

        foreach ($candidates as $binary) {
            $command = sprintf(
                '%s --host=%s --port=%s --user=%s --password=%s --databases %s'
                .' --single-transaction --quick --routines --events --triggers --default-character-set=utf8mb4'
                .' --result-file=%s 2>&1',
                escapeshellarg($binary),
                escapeshellarg($connection['host']),
                escapeshellarg((string) $connection['port']),
                escapeshellarg($connection['username']),
                escapeshellarg($connection['password']),
                escapeshellarg($connection['database']),
                escapeshellarg($fullPath)
            );

            @unlink($fullPath);
            @shell_exec($command);

            if (file_exists($fullPath) && filesize($fullPath) > 0) {
                return true;
            }
        }

        return false;
    }

    /** Same fallback the original uses when mysqldump isn't reachable: dump structure + data via PDO. */
    private function dumpWithPhp(string $fullPath): void
    {
        $pdo = DB::connection()->getPdo();

        $handle = fopen($fullPath, 'w');
        if (! $handle) {
            throw new \RuntimeException("Unable to write backup file: {$fullPath}");
        }

        fwrite($handle, "SET NAMES utf8mb4;\nSET FOREIGN_KEY_CHECKS=0;\n\n");

        $tables = array_map(fn ($row) => array_values((array) $row)[0], $pdo->query('SHOW TABLES')->fetchAll(\PDO::FETCH_NUM));

        foreach ($tables as $table) {
            $quoted = str_replace('`', '``', $table);
            $create = $pdo->query("SHOW CREATE TABLE `{$quoted}`")->fetch(\PDO::FETCH_ASSOC);
            fwrite($handle, "--\n-- Table structure for table `{$table}`\n--\n\n".($create['Create Table'] ?? '').";\n\n");

            $stmt = $pdo->query("SELECT * FROM `{$quoted}`");
            $batch = [];
            $columns = null;

            while ($row = $stmt->fetch(\PDO::FETCH_ASSOC)) {
                $columns ??= array_keys($row);
                $values = array_map(fn ($col) => is_null($row[$col]) ? 'NULL' : $pdo->quote($row[$col]), $columns);
                $batch[] = '('.implode(',', $values).')';

                if (count($batch) >= 500) {
                    $this->writeInsert($handle, $quoted, $columns, $batch);
                    $batch = [];
                }
            }

            if ($batch !== []) {
                $this->writeInsert($handle, $quoted, $columns, $batch);
            }

            fwrite($handle, "\n");
        }

        fwrite($handle, "SET FOREIGN_KEY_CHECKS=1;\n");
        fclose($handle);
    }

    private function writeInsert($handle, string $quotedTable, array $columns, array $batch): void
    {
        $columnList = '`'.implode('`,`', $columns).'`';
        fwrite($handle, "INSERT INTO `{$quotedTable}` ({$columnList}) VALUES ".implode(',', $batch).";\n");
    }
}
