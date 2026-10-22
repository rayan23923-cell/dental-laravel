<?php

namespace Tests\Feature;

use App\Models\LicenseAdmin;
use App\Models\LicenseUniversity;
use App\Models\OfflineLicense;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LicensingPortalTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): LicenseAdmin
    {
        return LicenseAdmin::create(['name' => 'Owner', 'username' => 'owner', 'password' => 'secret-password-1']);
    }

    public function test_portal_needs_its_own_account(): void
    {
        $this->get('/licensing')->assertRedirect('/licensing/login');

        // A clinic super admin is not a portal account.
        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->get('/licensing')->assertRedirect('/licensing/login');

        $this->get('/licensing/login')->assertOk()->assertSee('بوابة التراخيص');
    }

    public function test_sign_in_with_portal_account(): void
    {
        $this->admin();

        $this->post('/licensing/login', ['username' => 'owner', 'password' => 'wrong'])->assertSessionHasErrors('username');
        $this->post('/licensing/login', ['username' => 'owner', 'password' => 'secret-password-1'])->assertRedirect('/licensing');
        $this->assertAuthenticated('license');
        $this->assertGuest('web');
        $this->get('/licensing')->assertOk()->assertSee('الجامعات');
    }

    public function test_universities_codes_and_devices(): void
    {
        $this->actingAs($this->admin(), 'license');

        $this->post('/licensing/universities', ['name' => 'جامعة تكريت', 'contact' => '0770'])->assertSessionHasNoErrors();
        $university = LicenseUniversity::firstOrFail();
        $this->post('/licensing/universities', ['name' => 'جامعة تكريت'])->assertSessionHasErrors('name');

        $this->post("/licensing/universities/{$university->id}/codes", ['count' => 3])->assertSessionHasNoErrors();
        $this->assertSame(3, $university->licenses()->count());
        $code = $university->licenses()->first();
        $this->assertSame('جامعة تكريت', $code->university);

        // A computer activates, then its updater reports the build it runs.
        $machine = 'ABCD-1234-ABCD-1234';
        $this->postJson('/api/v1/offline/activate', ['code' => $code->code, 'machine_id' => $machine, 'machine_name' => 'RECEPTION', 'build' => 198])->assertOk();
        $this->assertSame(198, $code->fresh()->installed_build);
        $this->getJson("/api/v1/offline/latest?code={$code->code}&machine={$machine}&build=205")->assertOk();
        $this->assertSame(205, $code->fresh()->installed_build);

        $this->get("/licensing/universities/{$university->id}")->assertOk()
            ->assertSee('RECEPTION')->assertSee($machine)->assertSee('205');

        // A used code can't be deleted, nor its university; it can be freed.
        $this->delete("/licensing/codes/{$code->id}")->assertSessionHas('error');
        $this->delete("/licensing/universities/{$university->id}")->assertSessionHas('error');
        $this->patch("/licensing/codes/{$code->id}", ['action' => 'release'])->assertSessionHasNoErrors();
        $this->assertNull($code->fresh()->machine_id);

        $this->patch("/licensing/codes/{$code->id}", ['action' => 'revoke']);
        $this->postJson('/api/v1/offline/activate', ['code' => $code->code, 'machine_id' => $machine])->assertStatus(422);

        // Renaming keeps the name inside each code (it goes into the signed licence).
        $this->patch("/licensing/universities/{$university->id}", ['name' => 'Tikrit University'])->assertSessionHasNoErrors();
        $this->assertSame('Tikrit University', $code->fresh()->university);
    }

    public function test_each_university_activates_up_to_its_device_limit(): void
    {
        $this->actingAs($this->admin(), 'license');

        $this->post('/licensing/universities', ['name' => 'جامعة تكريت', 'max_devices' => 2])->assertSessionHasNoErrors();
        $university = LicenseUniversity::firstOrFail();
        $this->assertSame(2, $university->max_devices);
        $this->post("/licensing/universities/{$university->id}/codes", ['count' => 4]);
        [$a, $b, $c, $d] = $university->licenses()->orderBy('id')->get()->all();

        $activate = fn ($code, $machine) => $this->postJson('/api/v1/offline/activate', ['code' => $code->code, 'machine_id' => $machine]);
        $activate($a, 'AAAA-0000-0000-0001')->assertOk();
        $activate($b, 'AAAA-0000-0000-0002')->assertOk();
        // A third computer is refused; the second code on the same computer is not a new device.
        $activate($c, 'AAAA-0000-0000-0003')->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'الحد الأقصى'));
        $activate($c, 'AAAA-0000-0000-0002')->assertOk();
        // Already activated computers keep working (a reinstall).
        $activate($a, 'AAAA-0000-0000-0001')->assertOk();

        $this->get("/licensing/universities/{$university->id}")->assertOk()->assertSee('2 / 2');

        // Stopping a computer frees its place; restarting it then is over the limit.
        $this->patch("/licensing/codes/{$a->id}", ['action' => 'revoke']);
        $activate($d, 'AAAA-0000-0000-0003')->assertOk();
        $this->patch("/licensing/codes/{$a->id}", ['action' => 'restore'])->assertSessionHas('error');
        $this->assertNotNull($a->fresh()->revoked_at);

        // Raising the limit (or clearing it) lets it back in.
        $this->patch("/licensing/universities/{$university->id}", ['name' => 'جامعة تكريت', 'max_devices' => ''])->assertSessionHasNoErrors();
        $this->patch("/licensing/codes/{$a->id}", ['action' => 'restore'])->assertSessionHasNoErrors();
        $this->assertNull($a->fresh()->revoked_at);
        $this->post('/licensing/universities', ['name' => 'X', 'max_devices' => 0])->assertSessionHasErrors('max_devices');
    }

    public function test_codes_from_the_clinic_page_join_the_portal_university(): void
    {
        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->post('/offline-licenses', ['university' => 'جامعة الموصل', 'count' => 2])->assertSessionHasNoErrors();

        $university = LicenseUniversity::where('name', 'جامعة الموصل')->firstOrFail();
        $this->assertSame(2, $university->licenses()->count());
    }

    public function test_admin_command_creates_an_account(): void
    {
        $file = tempnam(sys_get_temp_dir(), 'lic');
        $this->artisan('licensing:admin', ['username' => 'hakam', '--password-file' => $file])->assertSuccessful();

        $this->assertTrue(LicenseAdmin::where('username', 'hakam')->exists());
        preg_match('/password: (\S+)/', file_get_contents($file), $m);
        unlink($file);
        $this->post('/licensing/login', ['username' => 'hakam', 'password' => $m[1]])->assertRedirect('/licensing');
    }
}
