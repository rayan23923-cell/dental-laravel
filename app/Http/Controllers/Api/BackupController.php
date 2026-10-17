<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicSetting;
use App\Services\DatabaseBackupService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * Mirrors App\Http\Controllers\BackupController for the Flutter client
 * (an admin screen there can show backup status and trigger one), same as
 * every other module in this port. download() (2026-10-17) is the web's
 * backup.download: the app saves the file and hands it to the system's
 * share/open sheet.
 */
class BackupController extends Controller
{
    public function status(DatabaseBackupService $backups): JsonResponse
    {
        $settings = ClinicSetting::current();

        return response()->json([
            'enabled' => (bool) $settings->enable_daily_backup,
            'last_backup_at' => $settings->last_backup_at?->toDateTimeString(),
            'files' => $backups->list(),
        ]);
    }

    public function store(DatabaseBackupService $backups): JsonResponse
    {
        $result = $backups->create();

        ClinicSetting::current()->update(['last_backup_at' => now()]);

        return response()->json(['message' => 'Backup created.', ...$result]);
    }

    public function toggleAuto(Request $request): JsonResponse
    {
        $validated = $request->validate(['enabled' => ['required', 'boolean']]);

        ClinicSetting::current()->update(['enable_daily_backup' => $validated['enabled']]);

        return response()->json(['message' => 'Updated.']);
    }

    public function download(string $filename, DatabaseBackupService $backups): BinaryFileResponse
    {
        $path = $backups->fullPath($filename);

        abort_if($path === null, 404);

        return response()->download($path, $filename);
    }
}
