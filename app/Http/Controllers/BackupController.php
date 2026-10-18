<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Services\DatabaseBackupService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Response as ResponseFacade;
use Inertia\Inertia;
use Inertia\Response;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * Ports admin/backup.php + admin/ajax/backup_db.php — manual backup button
 * and a daily-auto toggle. Gated the same way the original does (plain
 * `super_admin`/`admin` role check, no granular permission — see the
 * `role:super_admin,admin` route group), and excludes the MikroTik SCP
 * upload step entirely, per standing request.
 *
 * The original's "daily" backup only ever ran as a side effect of an admin
 * loading the dashboard (`fetch(...?action=auto)` in dashboard.php, guarded
 * by an "already done today" check) — no real cron, so a clinic where no
 * admin opened the dashboard on a given day silently got no backup that
 * day. Replaced here with a real Laravel-scheduled command
 * (App\Console\Commands\RunDatabaseBackup, see routes/console.php) that
 * runs independently of anyone visiting the page — see README for the
 * one-time OS scheduler setup this still requires.
 */
class BackupController extends Controller
{
    public function index(DatabaseBackupService $backups): Response
    {
        $settings = ClinicSetting::current();

        return Inertia::render('Backup/Index', [
            'enabled' => (bool) $settings->enable_daily_backup,
            'alwaysDaily' => (bool) config('backup.daily'),
            'folder' => $backups->dir(),
            'lastBackupAt' => $settings->last_backup_at?->toDateTimeString(),
            'files' => $backups->list(),
            // Only the hosted system hands its data to offline copies.
            'offlineCopy' => ! config('offline.edition'),
        ]);
    }

    public function store(DatabaseBackupService $backups): RedirectResponse
    {
        $result = $backups->create();

        ClinicSetting::current()->update(['last_backup_at' => now()]);

        return back()->with('success', "تم إنشاء نسخة احتياطية: {$result['filename']}");
    }

    public function toggleAuto(Request $request): RedirectResponse
    {
        $validated = $request->validate(['enabled' => ['required', 'boolean']]);

        ClinicSetting::current()->update(['enable_daily_backup' => $validated['enabled']]);

        return back();
    }

    /**
     * This database for the offline edition (2026-10-18, by request): the
     * offline control panel's "Restore" puts it in place. Sessions, queues,
     * tokens and server secrets are left out, see DatabaseBackupService.
     */
    public function offlineCopy(DatabaseBackupService $backups): BinaryFileResponse
    {
        @set_time_limit(0);

        return ResponseFacade::download($backups->createForOffline(), 'offline-copy_'.now()->format('Ymd_His').'.zip')->deleteFileAfterSend();
    }

    public function download(string $filename, DatabaseBackupService $backups): BinaryFileResponse
    {
        $path = $backups->fullPath($filename);

        abort_if($path === null, 404);

        return ResponseFacade::download($path, $filename);
    }
}
