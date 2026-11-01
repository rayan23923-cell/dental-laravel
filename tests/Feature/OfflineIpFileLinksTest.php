<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class OfflineIpFileLinksTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['app.url' => 'https://clinic.lan', 'filesystems.disks.public.url' => 'https://clinic.lan/storage']);
        Route::get('/_test/logo-url', fn () => Storage::disk('public')->url('logo.png'));
    }

    public function test_offline_server_opened_by_ip_links_files_on_that_ip(): void
    {
        config(['offline.edition' => true]);

        $this->get('https://192.168.68.52/_test/logo-url')->assertSee('https://192.168.68.52/storage/logo.png', false);
    }

    public function test_opened_by_name_keeps_app_url(): void
    {
        config(['offline.edition' => true]);

        $this->get('https://clinic.lan/_test/logo-url')->assertSee('https://clinic.lan/storage/logo.png', false);
    }

    public function test_hosted_system_is_unchanged(): void
    {
        config(['offline.edition' => false]);

        $this->get('https://192.168.68.52/_test/logo-url')->assertSee('https://clinic.lan/storage/logo.png', false);
    }
}
