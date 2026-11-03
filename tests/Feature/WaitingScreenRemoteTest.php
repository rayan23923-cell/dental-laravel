<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\WaitingScreenPairing;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Controlling paired waiting screens from the server (2026-11-03, by
 * request): the screen reports itself and picks up queued commands once.
 */
class WaitingScreenRemoteTest extends TestCase
{
    use RefreshDatabase;

    private function pairedScreen(): WaitingScreenPairing
    {
        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        return $pairing;
    }

    public function test_the_screen_reports_itself_and_receives_each_command_once(): void
    {
        $pairing = $this->pairedScreen();
        $device = json_encode(['app' => 'tv', 'version' => '1.1.340', 'open_on_boot' => true, 'return_minutes' => 5, 'secret' => 'x']);

        $this->getJson('/api/v1/waiting-screen?token='.$pairing->token.'&device='.urlencode($device))
            ->assertOk()->assertJsonPath('commands', []);

        $pairing->refresh();
        $this->assertNotNull($pairing->last_seen_at);
        $this->assertSame('1.1.340', $pairing->device['version']);
        $this->assertArrayNotHasKey('secret', $pairing->device);

        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)
            ->post("/waiting-screen/screens/{$pairing->id}/command", ['type' => 'return_minutes', 'value' => 10])
            ->assertSessionHasNoErrors();
        $this->actingAs($admin)
            ->post("/waiting-screen/screens/{$pairing->id}/command", ['type' => 'reload'])
            ->assertSessionHasNoErrors();
        $this->actingAs($admin)
            ->post("/waiting-screen/screens/{$pairing->id}/command", ['type' => 'return_minutes', 'value' => 7])
            ->assertSessionHasErrors('value');

        $commands = $this->getJson('/api/v1/waiting-screen?token='.$pairing->token)->json('commands');
        $this->assertSame([['type' => 'return_minutes', 'value' => 10], ['type' => 'reload', 'value' => null]], $commands);
        $this->getJson('/api/v1/waiting-screen?token='.$pairing->token)->assertJsonPath('commands', []);
    }

    public function test_staff_list_rename_and_unpair_screens_through_the_api(): void
    {
        $pairing = $this->pairedScreen();
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->getJson('/api/v1/waiting-screen/screens')->assertOk()->assertJsonPath('data.0.id', $pairing->id);
        $this->patchJson("/api/v1/waiting-screen/screens/{$pairing->id}", ['name' => 'شاشة المختبر'])
            ->assertOk()->assertJsonPath('data.name', 'شاشة المختبر');
        $this->postJson("/api/v1/waiting-screen/screens/{$pairing->id}/command", ['type' => 'open_on_boot', 'value' => false])
            ->assertOk()->assertJsonPath('data.pending', ['open_on_boot']);

        $this->deleteJson("/api/v1/waiting-screen/screens/{$pairing->id}")->assertOk();
        $this->getJson('/api/v1/waiting-screen?token='.$pairing->token)->assertJsonPath('paired', false);
    }

    public function test_staff_without_the_edit_permission_cannot_send_commands(): void
    {
        $pairing = $this->pairedScreen();

        $this->actingAs(User::factory()->create(['role' => 'reception']))
            ->post("/waiting-screen/screens/{$pairing->id}/command", ['type' => 'reload'])
            ->assertForbidden();
    }
}
