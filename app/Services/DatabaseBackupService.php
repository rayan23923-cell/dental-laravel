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

    /**
     * Tables an offline copy gets empty when it takes this database
     * (2026-10-18, by request): sessions, queues, tokens and the licensing
     * records belong to the hosted server only.
     */
    public const HOSTED_ONLY_TABLES = [
        'cache', 'cache_locks', 'sessions', 'jobs', 'job_batches', 'failed_jobs', 'queued_emails',
        'offline_licenses', 'license_admins', 'license_universities',
        'password_reset_tokens', 'password_reset_otps', 'personal_access_tokens', 'device_tokens',
        'scanner_pairings', 'waiting_screen_pairings', 'mikrotik_settings',
    ];

    /** Columns blanked in that copy: secrets of the hosted server (mail_password is encrypted with its APP_KEY anyway). */
    public const HOSTED_ONLY_COLUMNS = [
        'clinic_settings' => ['mail_password', 'mikrotik_ip', 'mikrotik_user', 'mikrotik_pass', 'mikrotik_ssh_port', 'jwt_secret_key'],
    ];

    /**
     * The hosted database for an offline copy, as a backup-style zip
     * (`database.sql`) in a temporary file the caller deletes. Always
     * the PHP dump, which can leave out the hosted-only rows and secrets.
     */
    public function createForOffline(): string
    {
        $sql = tempnam(sys_get_temp_dir(), 'offline-sync');
        $this->dumpWithPhp($sql, self::HOSTED_ONLY_TABLES, self::HOSTED_ONLY_COLUMNS);

        $zipPath = $sql.'.zip';
        $zip = new ZipArchive();
        if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
            @unlink($sql);
            throw new \RuntimeException("Unable to write {$zipPath}");
        }
        $zip->addFile($sql, 'database.sql');
        $zip->close();
        @unlink($sql);

        return $zipPath;
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
        [$sql, $temp] = $this->extract($path);

        try {
            if (filesize($sql) === 0) {
                throw new \RuntimeException("The backup is empty: {$path}");
            }
            [$portable, $filled] = $this->forMariaDb($sql);
            if ($temp) {
                @unlink($temp);
            }
            $temp = $sql = $portable;
            Schema::dropAllTables();
            $connection = config('database.connections.'.config('database.default'));
            if (! $this->importWithClient($connection, $sql)) {
                try {
                    $this->importWithPdo($sql);
                } finally {
                    // Back to the app's own sql_mode for what runs next (migrations).
                    DB::reconnect();
                }
            }
            $this->assertFilled($filled);
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

    /** The dump inside a backup: [sql path, temp file to delete or null]. */
    private function extract(string $path): array
    {
        if (! str_ends_with(strtolower($path), '.zip')) {
            return [$path, null];
        }
        $zip = new ZipArchive();
        if ($zip->open($path) !== true || ($contents = $zip->getFromName('database.sql')) === false) {
            throw new \RuntimeException("Not a backup zip (no database.sql): {$path}");
        }
        $zip->close();
        $temp = tempnam(sys_get_temp_dir(), 'restore');
        file_put_contents($temp, $contents);

        return [$temp, $temp];
    }

    /**
     * Tables never offered for a merge: the migrations record and what
     * belongs to one server only (sessions, queues, tokens, licensing).
     */
    public const NOT_MERGED = ['migrations', ...self::HOSTED_ONLY_TABLES];

    /** Names shown when choosing what to take from a backup (2026-10-20). */
    public const SECTION_LABELS = [
        'doctors' => 'الأطباء (الطلاب)',
        'users' => 'المستخدمون',
        'user_permissions' => 'صلاحيات المستخدمين',
        'register_services' => 'الخدمات وأسعارها',
        'register_days' => 'أيام التسجيل',
        'clinic_settings' => 'إعدادات العيادة',
        'education_types' => 'أنواع الدراسة',
        'stages' => 'المراحل',
        'departments' => 'الأقسام',
        'groups' => 'المجموعات',
        'academic_sessions' => 'السنوات الدراسية',
        'tasks' => 'المهام',
        'task_instances' => 'تقدم المهام',
        'case_sheet_types' => 'أنواع الكيس شيت',
        'patients_simple' => 'تسجيلات المرضى',
        'patients' => 'المرضى',
        'payments' => 'المدفوعات',
        'appointments' => 'المواعيد',
    ];

    /**
     * The tables a backup has, for choosing what to merge (2026-10-20):
     * name, label and whether it carries rows, in the dump's order.
     *
     * @return array<int, array{table: string, label: string, rows: bool}>
     */
    public function tablesIn(string $path): array
    {
        [$sql, $temp] = $this->extract($path);
        try {
            $tables = [];
            $in = fopen($sql, 'r');
            while (($line = fgets($in)) !== false) {
                if (preg_match('/^(?:CREATE TABLE|INSERT INTO) `((?:[^`]|``)+)`/', $line, $m)) {
                    $table = str_replace('``', '`', $m[1]);
                    $tables[$table] = ($tables[$table] ?? false) || str_starts_with($line, 'INSERT');
                }
            }
            fclose($in);
        } finally {
            if ($temp) {
                @unlink($temp);
            }
        }

        $out = [];
        foreach ($tables as $table => $rows) {
            if (! in_array($table, self::NOT_MERGED, true)) {
                $out[] = ['table' => $table, 'label' => self::SECTION_LABELS[$table] ?? $table, 'rows' => $rows];
            }
        }

        return $out;
    }

    /**
     * Adds what a backup has and this database lacks, for the chosen
     * tables only (2026-10-20, by request: taking a copy must not lose the
     * data already here). Nothing is dropped or overwritten: a missing
     * table is created, and each row goes in with INSERT IGNORE, so a row
     * whose id or unique key (e.g. a doctor's username) already exists is
     * kept as it is here. Returns rows added per table, and per-table
     * errors, so one table that doesn't fit doesn't stop the others.
     *
     * @param  array<int, string>  $tables
     * @return array{added: array<string, int>, errors: array<string, string>}
     */
    public function merge(string $path, array $tables): array
    {
        $wanted = array_flip(array_diff($tables, self::NOT_MERGED));
        [$sql, $temp] = $this->extract($path);
        $portable = null;
        $added = [];
        $errors = [];
        try {
            [$portable] = $this->forMariaDb($sql);
            $existing = [];
            foreach (Schema::getTableListing() as $name) {
                $existing[str_contains($name, '.') ? substr($name, strrpos($name, '.') + 1) : $name] = true;
            }

            $in = fopen($portable, 'r');
            $statement = '';
            while (($line = fgets($in)) !== false) {
                $statement .= $line;
                if (! str_ends_with(rtrim($line), ';')) {
                    continue;
                }
                $this->mergeStatement(trim($statement), $wanted, $existing, $added, $errors);
                $statement = '';
            }
            fclose($in);
        } finally {
            DB::reconnect();
            foreach ([$temp, $portable] as $file) {
                if ($file) {
                    @unlink($file);
                }
            }
        }

        $uploads = dirname($path).DIRECTORY_SEPARATOR.self::UPLOADS_DIR;
        if (is_dir($uploads)) {
            $this->copyNewer($uploads, storage_path('app/public'));
        }

        return ['added' => $added, 'errors' => $errors];
    }

    /** One statement of a dump during merge(); see there. */
    private function mergeStatement(string $statement, array $wanted, array &$existing, array &$added, array &$errors): void
    {
        if ($statement === '' || str_starts_with($statement, '--')) {
            return;
        }
        // Session settings (sql_mode, names, foreign keys) run as they are.
        if (preg_match('/^(?:SET\b|\/\*!\d+ SET\b)/i', $statement)) {
            DB::unprepared($statement);

            return;
        }
        if (! preg_match('/^(CREATE TABLE|INSERT INTO) `((?:[^`]|``)+)`/', $statement, $m)) {
            return; // DROP TABLE, LOCK/UNLOCK, ALTER ... KEYS, views: not needed to add rows
        }
        [$kind, $table] = [$m[1], str_replace('``', '`', $m[2])];
        if (! isset($wanted[$table]) || isset($errors[$table])) {
            return;
        }

        try {
            if ($kind === 'CREATE TABLE' && ! isset($existing[$table])) {
                DB::unprepared($statement);
                $existing[$table] = true;
            } elseif ($kind === 'INSERT INTO') {
                $count = DB::getPdo()->exec('INSERT IGNORE'.substr($statement, strlen('INSERT')));
                $added[$table] = ($added[$table] ?? 0) + (int) $count;
            }
        } catch (\Throwable $e) {
            $errors[$table] = mb_substr($e->getMessage(), 0, 300);
        }
    }

    /**
     * A copy of the dump that MariaDB (the offline package) also accepts
     * (2026-10-18): the hosted server runs MySQL 8, whose tables use the
     * utf8mb4_0900_* collations and /*!80016 ... *\/ options MariaDB
     * rejects, so a hosted copy restored offline used to fail after the
     * tables were dropped. Line by line, so a large dump isn't held in memory.
     * Also returns the tables the dump has rows for, to check afterwards.
     *
     * @return array{0: string, 1: array<int, string>}
     */
    private function forMariaDb(string $sql): array
    {
        $out = tempnam(sys_get_temp_dir(), 'restore');
        $in = fopen($sql, 'r');
        $to = fopen($out, 'w');
        $filled = [];
        // Rows as they are (2026-10-19): a row with id 0 keeps it, and the
        // zero dates older data has don't fail the strict mode MariaDB and
        // this app's connection use. The dump's own settings still follow.
        fwrite($to, "SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION';\nSET FOREIGN_KEY_CHECKS=0;\n");
        while (($line = fgets($in)) !== false) {
            if (str_contains($line, '_0900_') || str_contains($line, '/*!80')) {
                $line = preg_replace(['/\butf8mb4_0900_\w+/', '/\/\*!80\d{3}.*?\*\/\s?/'], ['utf8mb4_unicode_ci', ''], $line);
            }
            if (str_starts_with($line, 'INSERT INTO `') && preg_match('/^INSERT INTO `((?:[^`]|``)+)`/', $line, $m)) {
                $filled[str_replace('``', '`', $m[1])] = true;
            }
            fwrite($to, $line);
        }
        fclose($in);
        fclose($to);

        return [$out, array_keys($filled)];
    }

    /**
     * Runs the dump one statement at a time (2026-10-18): a whole file in
     * one unprepared call only reports an error in its first statement, so
     * a failing CREATE TABLE further down went unnoticed and the restore
     * "succeeded" with empty tables. Dumps escape newlines inside values,
     * so a line ending in `;` ends a statement.
     */
    private function importWithPdo(string $sql): void
    {
        $in = fopen($sql, 'r');
        $statement = '';
        try {
            while (($line = fgets($in)) !== false) {
                $statement .= $line;
                if (! str_ends_with(rtrim($line), ';')) {
                    continue;
                }
                try {
                    DB::unprepared($statement);
                } catch (\Throwable $e) {
                    throw new \RuntimeException('Import failed at: '.mb_substr(trim($statement), 0, 150).' ... '.$e->getMessage(), 0, $e);
                }
                $statement = '';
            }
            if (trim($statement) !== '') {
                DB::unprepared($statement);
            }
        } finally {
            fclose($in);
        }
    }

    /** Every table the dump has rows for must have come back with rows. */
    private function assertFilled(array $tables): void
    {
        $missing = array_values(array_filter($tables, fn ($t) => ! Schema::hasTable($t) || ! DB::table($t)->exists()));
        if ($missing !== []) {
            throw new \RuntimeException('The backup did not import fully, these tables came back empty: '.implode(', ', array_slice($missing, 0, 10)));
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
                // --complete-insert (2026-10-20): column names in each INSERT,
                // so merge() can add rows to a table whose columns are in another order.
                .' --single-transaction --quick --complete-insert --routines --events --triggers --default-character-set=utf8mb4'
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

    /**
     * Same fallback the original uses when mysqldump isn't reachable: dump structure + data via PDO.
     * `$structureOnly` tables get no rows; `$nullColumns` (table => columns) are written as NULL.
     */
    private function dumpWithPhp(string $fullPath, array $structureOnly = [], array $nullColumns = []): void
    {
        $pdo = DB::connection()->getPdo();

        $handle = fopen($fullPath, 'w');
        if (! $handle) {
            throw new \RuntimeException("Unable to write backup file: {$fullPath}");
        }

        fwrite($handle, "SET NAMES utf8mb4;\nSET FOREIGN_KEY_CHECKS=0;\nSET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION';\n\n");

        $tables = array_map(fn ($row) => array_values((array) $row)[0], $pdo->query('SHOW FULL TABLES WHERE Table_type = \'BASE TABLE\'')->fetchAll(\PDO::FETCH_NUM));

        foreach ($tables as $table) {
            $quoted = str_replace('`', '``', $table);
            $create = $pdo->query("SHOW CREATE TABLE `{$quoted}`")->fetch(\PDO::FETCH_ASSOC);
            fwrite($handle, "--\n-- Table structure for table `{$table}`\n--\n\nDROP TABLE IF EXISTS `{$quoted}`;\n".($create['Create Table'] ?? '').";\n\n");
            if (in_array($table, $structureOnly, true)) {
                continue;
            }
            $blank = $nullColumns[$table] ?? [];

            $stmt = $pdo->query("SELECT * FROM `{$quoted}`");
            $batch = [];
            $bytes = 0;
            $columns = null;

            while ($row = $stmt->fetch(\PDO::FETCH_ASSOC)) {
                $columns ??= array_keys($row);
                $values = array_map(fn ($col) => is_null($row[$col]) || in_array($col, $blank, true) ? 'NULL' : $pdo->quote($row[$col]), $columns);
                $batch[] = $tuple = '('.implode(',', $values).')';
                $bytes += strlen($tuple);

                // Also by size (2026-10-19), so rows holding signatures or
                // photos stay well under the server's max_allowed_packet.
                if (count($batch) >= 500 || $bytes >= 1048576) {
                    $this->writeInsert($handle, $quoted, $columns, $batch);
                    $batch = [];
                    $bytes = 0;
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
