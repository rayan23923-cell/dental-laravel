<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicSetting;
use App\Services\DatabaseBackupService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\BackupController for the Flutter client
 * (an admin screen there can show backup status and trigger one), same as
 * every other module in this port. No file-download endpoint here — the
 * original's own ajax script draws the same line (it returns metadata only;
 * the actual .sql links are plain `<a href>` tags to a static folder, not
 * routed through the ajax endpoint) — an admin who wants the raw dump uses
 * the web UI.
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
}
