<?php

namespace Tests\Feature;

use App\Models\OfflineLicense;
use App\Models\User;
use App\Support\OfflineLicensing;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class OfflineLicenseTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->onComputer('11111111-aaaa-bbbb-cccc-000000000001');
        @unlink(OfflineLicensing::path());
    }

    protected function tearDown(): void
    {
        @unlink(OfflineLicensing::path());
        putenv('DENTAL_MACHINE_GUID');
        OfflineLicensing::forgetMachineId();
        parent::tearDown();
    }

    private function onComputer(string $guid): string
    {
        putenv("DENTAL_MACHINE_GUID=$guid");
        OfflineLicensing::forgetMachineId();

        return OfflineLicensing::machineId();
    }

    private function activate(string $code, string $machine)
    {
        return $this->postJson('/api/v1/offline/activate', ['code' => $code, 'machine_id' => $machine, 'machine_name' => 'PC']);
    }

    public function test_super_admin_creates_codes(): void
    {
        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->post('/offline-licenses', ['university' => 'جامعة تكريت', 'count' => 3])->assertSessionHasNoErrors();

        $this->assertSame(3, OfflineLicense::count());
        $this->assertMatchesRegularExpression('/^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$/', OfflineLicense::first()->code);

        $this->actingAs(User::factory()->create(['role' => 'admin']))
            ->post('/offline-licenses', ['university' => 'x', 'count' => 1])->assertForbidden();
    }

    public function test_a_code_is_used_once_and_stays_with_its_computer(): void
    {
        $license = OfflineLicense::create(['code' => OfflineLicense::newCode(), 'university' => 'جامعة تكريت']);
        $first = OfflineLicensing::machineId();

        // Typed in lower case and without dashes still matches.
        $response = $this->activate(strtolower(str_replace('-', '', $license->code)), $first)->assertOk();
        $data = OfflineLicensing::verify($response->json('license'));
        $this->assertSame($first, $data['machine_id']);
        $this->assertSame('جامعة تكريت', $data['university']);
        $this->assertNotNull($license->fresh()->activated_at);

        // The same computer may activate again (a reinstall), another may not.
        $this->activate($license->code, $first)->assertOk();
        $other = $this->onComputer('22222222-aaaa-bbbb-cccc-000000000002');
        $this->activate($license->code, $other)->assertStatus(422)->assertJsonPath('message', 'رمز التفعيل هذا مستخدم على حاسوب آخر.');
        $this->activate('AAAA-BBBB-CCCC-DDDD', $other)->assertStatus(422);

        // Freed by the admin, it moves to the other computer.
        $this->actingAs(User::factory()->create(['role' => 'super_admin']))
            ->patch("/offline-licenses/{$license->id}", ['action' => 'release']);
        $this->activate($license->code, $other)->assertOk();

        $license->update(['revoked_at' => now()]);
        $this->activate($license->code, $other)->assertStatus(422);
    }

    public function test_a_tampered_licence_is_rejected(): void
    {
        $license = OfflineLicense::create(['code' => OfflineLicense::newCode(), 'university' => 'جامعة', 'machine_id' => OfflineLicensing::machineId(), 'activated_at' => now()]);
        $issued = OfflineLicensing::issue($license);
        $this->assertNotNull(OfflineLicensing::verify($issued));

        $issued['payload'] = str_replace(OfflineLicensing::machineId(), 'AAAA-AAAA-AAAA-AAAA', $issued['payload']);
        $this->assertNull(OfflineLicensing::verify($issued));
    }

    public function test_only_activated_computers_get_updates(): void
    {
        $machine = OfflineLicensing::machineId();
        $license = OfflineLicense::create(['code' => OfflineLicense::newCode(), 'university' => 'جامعة']);

        $this->getJson("/api/v1/offline/latest?code={$license->code}&machine=$machine")->assertForbidden();
        $this->activate($license->code, $machine)->assertOk();
        $this->getJson("/api/v1/offline/latest?code={$license->code}&machine=$machine")->assertOk();
        $this->getJson("/api/v1/offline/latest?code={$license->code}&machine=AAAA-AAAA-AAAA-AAAA")->assertForbidden();
    }

    public function test_the_offline_copy_works_only_once_activated_on_this_computer(): void
    {
        config(['offline.edition' => true, 'offline.activation' => true]);

        $this->get('/login')->assertRedirect('/activate');
        $this->getJson('/api/v1/branding')->assertForbidden();
        $this->get('/activate')->assertOk()->assertSee(OfflineLicensing::machineId());

        // The hosted system answers the activation.
        $license = OfflineLicense::create(['code' => 'ABCD-EFGH-JKMN-PQRS', 'university' => 'جامعة تكريت', 'machine_id' => OfflineLicensing::machineId(), 'activated_at' => now()]);
        Http::fake(['*/api/v1/offline/activate' => Http::response(['license' => OfflineLicensing::issue($license)])]);

        $this->post('/activate', ['code' => 'ABCD-EFGH-JKMN-PQRS'])->assertRedirect('/login');
        $this->get('/login')->assertOk();

        // Copied to another computer, it asks for activation again.
        $this->onComputer('33333333-aaaa-bbbb-cccc-000000000003');
        $this->get('/login')->assertRedirect('/activate');
    }

    public function test_a_refused_code_shows_the_reason(): void
    {
        config(['offline.edition' => true, 'offline.activation' => true]);
        Http::fake(['*/api/v1/offline/activate' => Http::response(['message' => 'رمز التفعيل هذا مستخدم على حاسوب آخر.'], 422)]);

        $this->from('/activate')->post('/activate', ['code' => 'ABCD-EFGH-JKMN-PQRS'])
            ->assertRedirect('/activate')->assertSessionHasErrors(['code' => 'رمز التفعيل هذا مستخدم على حاسوب آخر.']);
        $this->assertFileDoesNotExist(OfflineLicensing::path());
    }

    public function test_the_hosted_system_has_no_activation_page(): void
    {
        $this->get('/activate')->assertNotFound();
        $this->get('/login')->assertOk();
    }

    /** A published offline build in a throwaway public folder. */
    private function publishBuild(): void
    {
        $public = sys_get_temp_dir().'/offline-public-'.uniqid();
        mkdir("$public/downloads/offline", 0777, true);
        symlink(public_path('build'), "$public/build"); // the Vite manifest
        file_put_contents("$public/downloads/offline/DentalClinicOffline-500.zip", 'server-zip');
        file_put_contents("$public/downloads/offline/DentalClinicClientSetup-500.exe", 'client-exe');
        file_put_contents("$public/downloads/offline/latest.json", json_encode([
            'build' => 500, 'file' => 'DentalClinicOffline-500.zip', 'url' => 'https://x/downloads/offline/DentalClinicOffline-500.zip', 'size' => 10,
            'client_file' => 'DentalClinicClientSetup-500.exe', 'client_url' => 'https://x/downloads/offline/DentalClinicClientSetup-500.exe', 'client_size' => 10,
        ]));
        $this->app->usePublicPath($public);
    }

    public function test_the_offline_server_is_only_inside_the_site(): void
    {
        $this->publishBuild();

        // Not on the public download page any more (2026-10-24, by request).
        $this->get('/download')->assertOk()->assertDontSee('سيرفر الأوفلاين')->assertDontSee('DentalClinicOffline-500.zip');
        $this->get('/backup/offline-server/server')->assertRedirect('/login');

        $this->actingAs(User::factory()->create(['role' => 'doctor']))->get('/backup/offline-server/server')->assertForbidden();

        $admin = User::factory()->create(['role' => 'admin']);
        $this->actingAs($admin)->get('/backup')->assertInertia(fn ($page) => $page->where('offlineServer.build', 500)->where('offlineServer.hasClient', true));
        $this->actingAs($admin)->get('/backup/offline-server/server')->assertOk()->assertDownload('DentalClinicOffline-500.zip');
        $this->actingAs($admin)->get('/backup/offline-server/client')->assertOk()->assertDownload('DentalClinicClientSetup-500.exe');
        $this->actingAs($admin)->get('/backup/offline-server/other')->assertNotFound();

        // On the VPS nginx sends the file itself from its internal location.
        $this->actingAs($admin)->withServerVariables(['SERVER_SOFTWARE' => 'nginx/1.27.0'])->get('/backup/offline-server/server')
            ->assertOk()->assertHeader('X-Accel-Redirect', '/downloads/offline/DentalClinicOffline-500.zip');
    }

    public function test_an_activated_computer_updates_through_its_own_code(): void
    {
        $this->publishBuild();
        $machine = OfflineLicensing::machineId();
        $license = OfflineLicense::create(['code' => OfflineLicense::newCode(), 'university' => 'جامعة']);
        $this->activate($license->code, $machine)->assertOk();

        $url = $this->getJson("/api/v1/offline/latest?code={$license->code}&machine=$machine")
            ->assertOk()->assertJsonPath('build', 500)->assertJsonMissingPath('client_url')->json('url');
        $this->assertStringContainsString('/api/v1/offline/download?', $url);

        $this->get($url)->assertOk()->assertDownload('DentalClinicOffline-500.zip');
        $this->get("/api/v1/offline/download?code={$license->code}&machine=AAAA-AAAA-AAAA-AAAA")->assertForbidden();
    }

    public function test_the_panel_reports_its_tunnel_and_the_fixed_link_leads_to_it(): void
    {
        $machine = OfflineLicensing::machineId();
        $license = OfflineLicense::create(['code' => OfflineLicense::newCode(), 'university' => 'جامعة']);
        $report = fn (array $extra = []) => $this->postJson('/api/v1/offline/tunnel', array_merge([
            'code' => $license->code, 'machine' => $machine,
            'url' => 'https://red-blue-green.trycloudflare.com', 'panel_url' => 'https://one-two.trycloudflare.com',
        ], $extra));

        // Only the activated computer can set where the link leads.
        $report()->assertForbidden();
        $this->activate($license->code, $machine)->assertOk();
        $report(['machine' => 'AAAA-AAAA-AAAA-AAAA'])->assertForbidden();
        $report(['url' => 'http://plain.example.com'])->assertUnprocessable();

        $link = $report()->assertOk()->json('link');
        $slug = $license->fresh()->tunnel_slug;
        $this->assertMatchesRegularExpression('/^[a-z0-9]{12}$/', $slug);
        $this->assertStringEndsWith("/go/$slug", $link);
        $this->get("/go/$slug")->assertRedirect('https://red-blue-green.trycloudflare.com');
        $this->get("/go/$slug/control")->assertRedirect('https://one-two.trycloudflare.com');

        // A new tunnel address keeps the same link.
        $report(['url' => 'https://new-address.trycloudflare.com'])->assertOk()->assertJsonPath('link', $link);
        $this->get("/go/$slug")->assertRedirect('https://new-address.trycloudflare.com');

        // The super admin's codes page on the hosting shows the fixed links.
        $this->actingAs(User::factory()->create(['role' => 'super_admin']))->get('/offline-licenses')
            ->assertInertia(fn ($page) => $page->where('licenses.0.tunnel_link', $link)
                ->where('licenses.0.tunnel_online', true)->where('licenses.0.tunnel_panel_link', "$link/control"));

        // Turned off, or not heard from for a while: a page that says so.
        $report(['url' => null, 'panel_url' => null])->assertOk();
        $this->get("/go/$slug")->assertStatus(503)->assertSee('غير متصل');
        $report()->assertOk();
        $this->travel(20)->minutes();
        $this->get("/go/$slug")->assertStatus(503);
        $this->get('/go/unknownslug123')->assertNotFound();
    }
}
