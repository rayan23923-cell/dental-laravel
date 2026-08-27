<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * One-shot diagnostic for the exact class of bug found twice in one day on
 * production (2026-08-27, see README.md): `2024_01_01_000000_import_clinic_schema`
 * was marked already-run on production rather than executed, on the
 * assumption its tables already matched `database/schema_import.sql` — an
 * assumption that turned out to be wrong in specific, narrow ways (missing
 * `academic_session_id` columns, then a missing AUTO_INCREMENT on
 * `academic_sessions.id`). Rather than keep discovering these one real-user
 * bug report at a time, this parses every `CREATE TABLE`/`ADD PRIMARY
 * KEY`/`MODIFY ... AUTO_INCREMENT` statement out of the same SQL file the
 * assumption was based on, and diffs it against whatever database this
 * command is actually run against via `information_schema` — read-only,
 * changes nothing. Intended to be run once against production
 * (`php artisan schema:diagnose`) to surface every remaining gap at once
 * instead of reactively, one support ticket at a time.
 */
class DiagnoseSchemaDrift extends Command
{
    protected $signature = 'schema:diagnose';

    protected $description = 'Compare the live database against database/schema_import.sql and report every structural gap (missing tables, columns, primary keys, or AUTO_INCREMENT) — read-only.';

    public function handle(): int
    {
        $sql = file_get_contents(database_path('schema_import.sql'));
        $connection = DB::connection()->getDatabaseName();

        $expectedColumns = $this->parseColumns($sql);
        $expectedPrimaryKeys = $this->parsePrimaryKeys($sql);
        $expectedAutoIncrement = $this->parseAutoIncrement($sql);

        $issues = [];

        // `information_schema`'s own column-name casing (TABLE_NAME vs
        // table_name) isn't consistent across MySQL/MariaDB versions —
        // production returned uppercase keys where local dev returned
        // lowercase, which crashed this on first run there. Normalizing
        // every row through `array_change_key_case` up front sidesteps
        // that instead of guessing at one server's behavior.
        $normalize = fn ($row) => array_change_key_case((array) $row, CASE_LOWER);

        $liveColumns = collect(DB::table('information_schema.columns')
            ->where('table_schema', $connection)
            ->select('table_name', 'column_name', 'extra')
            ->get())
            ->map($normalize)
            ->groupBy('table_name');

        $livePrimaryKeys = collect(DB::table('information_schema.key_column_usage')
            ->where('table_schema', $connection)
            ->where('constraint_name', 'PRIMARY')
            ->get(['table_name']))
            ->map($normalize)
            ->pluck('table_name')
            ->flip();

        foreach ($expectedColumns as $table => $columns) {
            if (! $liveColumns->has($table)) {
                $issues[] = "TABLE MISSING: `{$table}` (expected in schema_import.sql, not found on this database)";
                continue;
            }

            $liveColumnNames = $liveColumns[$table]->pluck('column_name')->flip();
            foreach ($columns as $column) {
                if (! $liveColumnNames->has($column)) {
                    $issues[] = "COLUMN MISSING: `{$table}`.`{$column}`";
                }
            }
        }

        foreach ($expectedPrimaryKeys as $table) {
            if ($liveColumns->has($table) && ! $livePrimaryKeys->has($table)) {
                $issues[] = "PRIMARY KEY MISSING: `{$table}` has no primary key";
            }
        }

        foreach ($expectedAutoIncrement as $table => $column) {
            if (! $liveColumns->has($table)) {
                continue; // already reported as TABLE MISSING above
            }

            $row = $liveColumns[$table]->firstWhere('column_name', $column);
            if ($row && ! str_contains(strtolower($row['extra'] ?? ''), 'auto_increment')) {
                $issues[] = "AUTO_INCREMENT MISSING: `{$table}`.`{$column}`";
            }
        }

        if (empty($issues)) {
            $this->info('No drift found — this database matches schema_import.sql exactly.');

            return self::SUCCESS;
        }

        $this->warn(count($issues).' issue(s) found:');
        foreach ($issues as $issue) {
            $this->line('  - '.$issue);
        }

        return self::FAILURE;
    }

    /** @return array<string, list<string>> table name => column names */
    private function parseColumns(string $sql): array
    {
        $tables = [];

        preg_match_all('/CREATE TABLE `(\w+)` \((.*?)\n\)/s', $sql, $matches, PREG_SET_ORDER);
        foreach ($matches as $match) {
            [, $table, $body] = $match;
            preg_match_all('/^\s*`(\w+)`/m', $body, $columnMatches);
            $tables[$table] = $columnMatches[1];
        }

        return $tables;
    }

    /** @return list<string> table names expected to have a primary key */
    private function parsePrimaryKeys(string $sql): array
    {
        preg_match_all('/ALTER TABLE `(\w+)`\s*\n\s*ADD PRIMARY KEY/', $sql, $matches);

        return $matches[1];
    }

    /** @return array<string, string> table name => auto-increment column name */
    private function parseAutoIncrement(string $sql): array
    {
        $result = [];

        preg_match_all('/ALTER TABLE `(\w+)`\s*\n\s*MODIFY `(\w+)`[^;]*AUTO_INCREMENT/', $sql, $matches, PREG_SET_ORDER);
        foreach ($matches as $match) {
            $result[$match[1]] = $match[2];
        }

        return $result;
    }
}
