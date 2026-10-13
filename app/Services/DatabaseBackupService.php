<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Schema;
use ZipArchive;

/**
 * Ports admin/ajax/backup_db.php's `create_backup()` — mysqldump first,
 * falling back to a PHP-driven dump when `mysqldump` isn't reachable
 * (matches the original's own two-candidate-paths-then-PHP-fallback
 * strategy, minus the MikroTik SCP upload step, which is out of scope by
 * request — see App\Models\ClinicSetting docblock).
 *
 * Since 2026-10-13 (by request, so updating or replacing the offline
 * package can't lose data) a backup is a zip holding `database.sql`, and
 * the uploaded files (photos, logos) are mirrored into an `uploads` folder
 * beside the zips: copying that folder keeps every photo once instead of
 * once per backup. The folder is `config('backup.path')`, outside the
 * program folder in the offline package; `restore()` puts both back.
 * Older `.sql`-only backups are still listed, downloadable and restorable.
 *
 * Downloading goes through BackupController::download, behind the same
 * admin-only route gate as everything else here.
 */
class DatabaseBackupService
{
    public const UPLOADS_DIR = 'uploads';

    public function dir(): string
    {
        $dir = rtrim(config('backup.path') ?: storage_path('app/private/backups'), '\\/');
        File::ensureDirectoryExists($dir);

        return $dir;
    }

    /** `$suffix` marks why it was made, e.g. "before-update". */
    public function create(string $suffix = ''): array
    {
        $connection = config('database.connections.'.config('database.default'));
        $dir = $this->dir();
        $name = $connection['database'].'_'.now()->format('Ymd_His').($suffix !== '' ? '_'.$suffix : '');
        $sql = $dir.DIRECTORY_SEPARATOR.$name.'.sql';

        if (! $this->dumpWithMysqldump($connection, $sql)) {
            $this->dumpWithPhp($sql);
        }

        $file = $sql;
        if (class_exists(ZipArchive::class)) {
            $zip = new ZipArchive();
            if ($zip->open($dir.DIRECTORY_SEPARATOR.$name.'.zip', ZipArchive::CREATE | ZipArchive::OVERWRITE) === true) {
                $zip->addFile($sql, 'database.sql');
                $zip->close();
                @unlink($sql);
                $file = $dir.DIRECTORY_SEPARATOR.$name.'.zip';
            }
        }

        $this->mirrorUploads();
        $this->prune();

        return ['filename' => basename($file), 'size' => filesize($file)];
    }

    /** @return array<int, array{name: string, size: int, mtime: int}> */
    public function list(): array
    {
        return array_slice($this->files(), 0, 10);
    }

    public function fullPath(string $filename): ?string
    {
        // Reject anything that isn't a bare filename before it ever touches
        // the filesystem — path separators or `..` would let a crafted
        // download request escape the backups directory.
        if ($filename !== basename($filename) || ! preg_match('/\.(sql|zip)$/', $filename)) {
            return null;
        }

        $path = $this->dir().DIRECTORY_SEPARATOR.$filename;

        return is_file($path) ? $path : null;
    }

    /**
     * Replaces the database with the backup's, and copies back the
     * uploaded files from the `uploads` folder beside it. Tables the backup
     * doesn't have are dropped too, so migrations can run cleanly after.
     */
    public function restore(string $path): void
    {
        $sql = $path;
        $temp = null;
        if (str_ends_with(strtolower($path), '.zip')) {
            $zip = new ZipArchive();
            if ($zip->open($path) !== true || ($contents = $zip->getFromName('database.sql')) === false) {
                throw new \RuntimeException("Not a backup zip (no database.sql): {$path}");
            }
            $zip->close();
            $temp = $sql = tempnam(sys_get_temp_dir(), 'restore');
            file_put_contents($temp, $contents);
            unset($contents);
        }

        try {
            if (filesize($sql) === 0) {
                throw new \RuntimeException("The backup is empty: {$path}");
            }
            Schema::dropAllTables();
            $connection = config('database.connections.'.config('database.default'));
            if (! $this->importWithClient($connection, $sql)) {
                DB::unprepared(file_get_contents($sql));
            }
        } finally {
            if ($temp) {
                @unlink($temp);
            }
        }

        $uploads = dirname($path).DIRECTORY_SEPARATOR.self::UPLOADS_DIR;
        if (is_dir($uploads)) {
            $this->copyNewer($uploads, storage_path('app/public'));
        }
    }

    /** @return array<int, array{name: string, size: int, mtime: int}> newest first */
    private function files(): array
    {
        $files = array_merge(glob($this->dir().DIRECTORY_SEPARATOR.'*.zip') ?: [], glob($this->dir().DIRECTORY_SEPARATOR.'*.sql') ?: []);
        $rows = array_map(fn ($path) => ['name' => basename($path), 'size' => filesize($path), 'mtime' => filemtime($path)], $files);
        usort($rows, fn ($a, $b) => [$b['mtime'], $b['name']] <=> [$a['mtime'], $a['name']]);

        return $rows;
    }

    private function prune(): void
    {
        $keep = (int) config('backup.keep');
        if ($keep <= 0) {
            return;
        }
        foreach (array_slice($this->files(), $keep) as $old) {
            @unlink($this->dir().DIRECTORY_SEPARATOR.$old['name']);
        }
    }

    /** Copies uploaded files that are new or changed into the mirror; never deletes from it. */
    private function mirrorUploads(): void
    {
        $source = storage_path('app/public');
        if (is_dir($source)) {
            $this->copyNewer($source, $this->dir().DIRECTORY_SEPARATOR.self::UPLOADS_DIR);
        }
    }

    private function copyNewer(string $from, string $to): void
    {
        foreach (File::allFiles($from, true) as $file) {
            if ($file->getFilename() === '.gitignore') {
                continue;
            }
            $target = $to.DIRECTORY_SEPARATOR.$file->getRelativePathname();
            if (is_file($target) && filesize($target) === $file->getSize() && filemtime($target) >= $file->getMTime()) {
                continue;
            }
            File::ensureDirectoryExists(dirname($target));
            copy($file->getPathname(), $target);
            touch($target, $file->getMTime());
        }
    }

    /**
     * MariaDB's own tools first (the offline package puts its bundled ones
     * on PATH), then XAMPP's, then MySQL's.
     */
    private function binaries(string $tool): array
    {
        return $tool === 'dump'
            ? ['mariadb-dump', 'C:\\xampp\\mysql\\bin\\mysqldump.exe', 'mysqldump']
            : ['mariadb', 'C:\\xampp\\mysql\\bin\\mysql.exe', 'mysql'];
    }

    private function connectionArgs(array $connection): string
    {
        return sprintf(
            ' --host=%s --port=%s --user=%s --password=%s',
            escapeshellarg($connection['host']),
            escapeshellarg((string) $connection['port']),
            escapeshellarg($connection['username']),
            escapeshellarg((string) $connection['password'])
        );
    }

    private function dumpWithMysqldump(array $connection, string $fullPath): bool
    {
        if (! function_exists('exec')) {
            return false;
        }

        foreach ($this->binaries('dump') as $binary) {
            $command = escapeshellarg($binary).$this->connectionArgs($connection)
                .' --single-transaction --quick --routines --events --triggers --default-character-set=utf8mb4'
                .' --result-file='.escapeshellarg($fullPath).' '.escapeshellarg($connection['database']).' 2>&1';

            @unlink($fullPath);
            $output = [];
            @exec($command, $output, $code);

            if ($code === 0 && file_exists($fullPath) && filesize($fullPath) > 0) {
                return true;
            }
        }

        @unlink($fullPath);

        return false;
    }

    private function importWithClient(array $connection, string $sql): bool
    {
        if (! function_exists('exec')) {
            return false;
        }

        foreach ($this->binaries('client') as $binary) {
            $command = escapeshellarg($binary).$this->connectionArgs($connection)
                .' --default-character-set=utf8mb4 '.escapeshellarg($connection['database'])
                .' < '.escapeshellarg($sql).' 2>&1';
            $output = [];
            @exec($command, $output, $code);
            if ($code === 0) {
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

        $tables = array_map(fn ($row) => array_values((array) $row)[0], $pdo->query('SHOW FULL TABLES WHERE Table_type = \'BASE TABLE\'')->fetchAll(\PDO::FETCH_NUM));

        foreach ($tables as $table) {
            $quoted = str_replace('`', '``', $table);
            $create = $pdo->query("SHOW CREATE TABLE `{$quoted}`")->fetch(\PDO::FETCH_ASSOC);
            fwrite($handle, "--\n-- Table structure for table `{$table}`\n--\n\nDROP TABLE IF EXISTS `{$quoted}`;\n".($create['Create Table'] ?? '').";\n\n");

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
