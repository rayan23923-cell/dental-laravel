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

    public function test_the_copy_for_the_offline_system_leaves_out_server_only_data_and_restores(): void
    {
        $admin = User::factory()->create(['username' => 'hostadmin', 'role' => 'admin']);
        \App\Models\ClinicSetting::current()->update(['mail_password' => 'smtp-secret']);
        \Illuminate\Support\Facades\DB::table('sessions')->insert(['id' => 'sess-1', 'payload' => 'x', 'last_activity' => time()]);

        $response = $this->actingAs($admin)->get(route('backup.offline-copy'));
        $response->assertOk();
        $file = $response->baseResponse->getFile()->getPathname();
        $zip = new ZipArchive();
        $zip->open($file);
        $sql = $zip->getFromName('database.sql');
        $zip->close();
        $copy = $this->dir.'/offline-copy.zip';
        File::ensureDirectoryExists($this->dir);
        copy($file, $copy);

        $this->assertStringContainsString('hostadmin', $sql);
        $this->assertStringContainsString('CREATE TABLE `sessions`', $sql);
        $this->assertStringNotContainsString('sess-1', $sql);
        $this->assertStringNotContainsString(\App\Models\ClinicSetting::current()->getRawOriginal('mail_password'), $sql);

        $this->artisan('backup:restore', ['file' => $copy, '--force' => true])->assertSuccessful();
        $this->assertDatabaseHas('users', ['username' => 'hostadmin']);
        $this->assertNull(\App\Models\ClinicSetting::current()->mail_password);

        $this->actingAs(User::factory()->create(['role' => 'doctor']))->get(route('backup.offline-copy'))->assertForbidden();
    }

    /** A copy from the hosted MySQL 8 server, with its collations and version comments, restores on MariaDB. */
    public function test_a_mysql_8_copy_restores_on_mariadb(): void
    {
        User::factory()->create(['username' => 'fromhost', 'role' => 'doctor']);
        $sql = $this->dump();
        $sql = preg_replace('/(\) ENGINE=InnoDB[^;]*?) COLLATE=\w+/', "$1 COLLATE=utf8mb4_0900_ai_ci /*!80016 DEFAULT ENCRYPTION='N' */", $sql);
        $sql = str_replace('COLLATE utf8mb4_unicode_ci', 'COLLATE utf8mb4_0900_ai_ci', $sql);
        $this->assertStringContainsString('utf8mb4_0900_ai_ci', $sql);
        $file = $this->zipped($sql);
        User::where('username', 'fromhost')->delete();

        $this->artisan('backup:restore', ['file' => $file, '--force' => true])->assertSuccessful();
        $this->assertDatabaseHas('users', ['username' => 'fromhost']);
    }

    /** A copy that breaks halfway doesn't leave empty tables: the data from before comes back and it says why. */
    public function test_a_restore_that_fails_puts_the_previous_data_back(): void
    {
        User::factory()->create(['username' => 'before', 'role' => 'doctor']);
        $sql = str_replace('INSERT INTO `users`', "CREATE TABLE `broken` (`x` not_a_type);\nINSERT INTO `users`", $this->dump());
        $file = $this->zipped($sql);

        $this->artisan('backup:restore', ['file' => $file, '--force' => true])
            ->expectsOutputToContain('Restore failed')
            ->assertFailed();
        $this->assertDatabaseHas('users', ['username' => 'before']);
    }

    private function dump(): string
    {
        $file = app(\App\Services\DatabaseBackupService::class)->createForOffline();
        $zip = new ZipArchive();
        $zip->open($file);
        $sql = $zip->getFromName('database.sql');
        $zip->close();
        @unlink($file);

        return $sql;
    }

    private function zipped(string $sql): string
    {
        File::ensureDirectoryExists($this->dir);
        $path = $this->dir.'/copy-'.uniqid().'.zip';
        $zip = new ZipArchive();
        $zip->open($path, ZipArchive::CREATE);
        $zip->addFromString('database.sql', $sql);
        $zip->close();

        return $path;
    }
}
