<?php

/*
 * Database and uploads backups (App\Services\DatabaseBackupService).
 *
 * The offline Windows package sets BACKUP_PATH to a folder outside the
 * program folder (C:\DentalClinicBackups by default, from config.txt's
 * BACKUP_DIR), so replacing or deleting the program never takes the
 * backups with it, and turns BACKUP_DAILY on (2026-10-13, by request).
 */
return [
    // Where backups are written: one zip per backup holding database.sql,
    // and an `uploads` folder beside them mirroring the uploaded files.
    'path' => env('BACKUP_PATH') ?: storage_path('app/private/backups'),

    // How many backups to keep; older ones are deleted. 0 keeps all.
    'keep' => (int) env('BACKUP_KEEP', 30),

    // Back up every day even when the daily toggle on the backup page is off.
    'daily' => (bool) env('BACKUP_DAILY', false),
];
