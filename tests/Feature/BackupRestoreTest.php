<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\RefreshDatabaseState;
use Illuminate\Support\Facades\File;
use Tests\TestCase;
use ZipArchive;

/**
 * Backups of the database and uploaded files, and putting them back
 * (2026-10-13). Real dumps and imports, so no wrapping transaction: the
 * next test that refreshes the database starts from a fresh one.
 */
class BackupRestoreTest extends TestCase
{
    use RefreshDatabase;

    protected $connectionsToTransact = [];

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/backup-test-'.uniqid();
        config(['backup.path' => $this->dir, 'backup.keep' => 3]);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        File::deleteDirectory(storage_path('app/public/backup-test'));
        RefreshDatabaseState::$migrated = false;
        parent::tearDown();
    }

    public function test_a_backup_holds_the_database_and_mirrors_uploads_and_restores_both(): void
    {
        $user = User::factory()->create(['username' => 'keepme', 'role' => 'admin']);
        File::ensureDirectoryExists(storage_path('app/public/backup-test'));
        File::put(storage_path('app/public/backup-test/form.jpg'), 'photo-bytes');

        $this->artisan('backup:run --force')->assertSuccessful();
        $zips = glob($this->dir.'/*.zip');
        $this->assertCount(1, $zips);
        $zip = new ZipArchive();
        $zip->open($zips[0]);
        $this->assertStringContainsString('keepme', $zip->getFromName('database.sql'));
        $zip->close();
        $this->assertSame('photo-bytes', File::get($this->dir.'/uploads/backup-test/form.jpg'));

        // Data lost after the backup comes back, with the photo.
        $user->delete();
        File::delete(storage_path('app/public/backup-test/form.jpg'));
        $this->artisan('backup:restore', ['file' => basename($zips[0]), '--force' => true])->assertSuccessful();

        $this->assertDatabaseHas('users', ['username' => 'keepme']);
        $this->assertSame('photo-bytes', File::get(storage_path('app/public/backup-test/form.jpg')));
        // The state before restoring was saved too.
        $this->assertCount(1, glob($this->dir.'/*_before-restore.zip'));
    }

    public function test_before_update_backs_up_only_when_migrations_are_pending_and_old_ones_are_pruned(): void
    {
        $this->artisan('backup:run --before-update')->expectsOutputToContain('No update')->assertSuccessful();
        $this->assertSame([], glob($this->dir.'/*.zip') ?: []);

        foreach (range(1, 4) as $i) {
            $this->artisan('backup:run --force')->assertSuccessful();
            sleep(1);
        }
        $this->assertCount(3, glob($this->dir.'/*.zip'));
    }

    public function test_the_daily_run_follows_the_offline_setting_once_a_day(): void
    {
        $this->artisan('backup:run')->expectsOutputToContain('disabled')->assertSuccessful();

        config(['backup.daily' => true]);
        $this->artisan('backup:run')->expectsOutputToContain('Backup created')->assertSuccessful();
        $this->artisan('backup:run')->expectsOutputToContain('already ran today')->assertSuccessful();
    }
}
