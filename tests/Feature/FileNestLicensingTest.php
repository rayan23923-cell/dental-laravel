<?php

namespace Tests\Feature;

use App\Models\LicenseAdmin;
use App\Models\LicenseUniversity;
use App\Models\OfflineLicense;
use App\Support\OfflineLicensing;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** One licensing portal for the clinic system and FileNest (2026-11-05). */
class FileNestLicensingTest extends TestCase
{
    use RefreshDatabase;

    private const MACHINE = 'ABCD-1234-ABCD-1234';

    public function test_the_portal_makes_codes_for_each_system(): void
    {
        $this->actingAs(LicenseAdmin::create(['name' => 'Owner', 'username' => 'owner', 'password' => 'secret-password-1']), 'license');
        $this->post('/licensing/universities', ['name' => 'جامعة تكريت', 'max_devices' => 1])->assertSessionHasNoErrors();
        $university = LicenseUniversity::firstOrFail();

        $this->post("/licensing/universities/{$university->id}/codes", ['count' => 2, 'product' => 'filenest'])->assertSessionHasNoErrors();
        $this->post("/licensing/universities/{$university->id}/codes", ['count' => 1])->assertSessionHasNoErrors();
        $this->post("/licensing/universities/{$university->id}/codes", ['count' => 1, 'product' => 'other'])->assertSessionHasErrors('product');

        $this->assertSame(2, OfflineLicense::where('product', 'filenest')->count());
        $this->assertSame(1, OfflineLicense::where('product', 'dental')->count());

        $this->get("/licensing/universities/{$university->id}?product=filenest")->assertOk()
            ->assertSee('FileNest (الملفات والمكتبة)');
    }

    public function test_a_filenest_code_activates_only_filenest(): void
    {
        $university = LicenseUniversity::create(['name' => 'جامعة تكريت', 'max_devices' => 1]);
        $files = OfflineLicense::create(['code' => 'AAAA-BBBB-CCCC-DDDD', 'product' => 'filenest', 'university' => $university->name, 'university_id' => $university->id]);
        $clinic = OfflineLicense::create(['code' => 'EEEE-FFFF-GGGG-HHHH', 'university' => $university->name, 'university_id' => $university->id]);

        // The clinic system sends no product: a FileNest code is refused there.
        $this->postJson('/api/v1/offline/activate', ['code' => $files->code, 'machine_id' => self::MACHINE])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'FileNest'));
        $this->postJson('/api/v1/offline/activate', ['code' => $clinic->code, 'machine_id' => self::MACHINE, 'product' => 'filenest'])
            ->assertStatus(422);

        $license = $this->postJson('/api/v1/offline/activate', ['code' => $files->code, 'machine_id' => self::MACHINE, 'product' => 'filenest', 'build' => 30])
            ->assertOk()->json('license');
        $this->assertSame('filenest', OfflineLicensing::verify($license)['product']);

        // The device limit counts each system on its own.
        $this->postJson('/api/v1/offline/activate', ['code' => $clinic->code, 'machine_id' => 'ABCD-1234-ABCD-9999'])->assertOk();

        // FileNest's panel checks in; its packages come from its own hosting.
        $this->getJson('/api/v1/offline/latest?code='.$files->code.'&machine='.self::MACHINE.'&build=31')
            ->assertOk()->assertJson(['build' => 0, 'product' => 'filenest']);
        $this->assertSame(31, $files->fresh()->installed_build);
    }
}
