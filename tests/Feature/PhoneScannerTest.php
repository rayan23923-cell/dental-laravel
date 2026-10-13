<?php

namespace Tests\Feature;

use App\Models\ScannerPairing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PhoneScannerTest extends TestCase
{
    use RefreshDatabase;

    public function test_phone_scans_reach_the_computer_that_paired_it(): void
    {
        $user = User::factory()->create(['role' => 'admin']);

        $pairing = $this->actingAs($user)->postJson('/scanner-pairings')->assertCreated()->json('data');
        $this->assertMatchesRegularExpression('/^\d{6}$/', $pairing['code']);
        $this->assertStringStartsWith('data:image/png;base64,', $pairing['qr']);
        $this->assertFalse($pairing['phone_joined']);
        $token = ScannerPairing::findOrFail($pairing['id'])->token;
        $this->assertStringEndsWith("/scan/{$token}", $pairing['url']);

        // The phone, with no login: the code leads to the scanner page.
        auth()->logout();
        $this->post('/scan', ['code' => $pairing['code'] === '000000' ? '999999' : '000000'])->assertSessionHasErrors('code');
        $this->post('/scan', ['code' => $pairing['code']])->assertRedirect(route('phone-scanner.show', $token));
        $this->get("/scan/{$token}")->assertOk()->assertInertia(fn ($p) => $p->component('PhoneScanner/Scan')->where('token', $token));
        $this->postJson("/scan/{$token}/scans", ['payload' => 'REG-1'])->assertCreated();
        $this->postJson("/scan/{$token}/scans", ['payload' => 'REG-2'])->assertCreated();
        $this->get('/scan/not-a-token')->assertNotFound();

        $first = $this->actingAs($user)->getJson("/scanner-pairings/{$pairing['id']}/scans")->assertOk()->json('data');
        $this->assertTrue($first['phone_joined']);
        $this->assertSame(['REG-1', 'REG-2'], array_column($first['scans'], 'payload'));

        $after = $first['scans'][0]['id'];
        $this->getJson("/scanner-pairings/{$pairing['id']}/scans?after={$after}")
            ->assertJsonPath('data.scans.0.payload', 'REG-2')->assertJsonCount(1, 'data.scans');

        // Someone else's computer can't read it; ending it stops the phone.
        $other = User::factory()->create(['role' => 'admin']);
        $this->actingAs($other)->getJson("/scanner-pairings/{$pairing['id']}/scans")->assertNotFound();
        $this->actingAs($user)->deleteJson("/scanner-pairings/{$pairing['id']}")->assertOk();
        $this->postJson("/scan/{$token}/scans", ['payload' => 'REG-3'])->assertStatus(410);
    }

    public function test_an_expired_pairing_is_closed_to_both_sides(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        $pairing = ScannerPairing::open($user);
        $pairing->update(['expires_at' => now()->subMinute()]);

        $this->post('/scan', ['code' => $pairing->code])->assertSessionHasErrors('code');
        $this->postJson("/scan/{$pairing->token}/scans", ['payload' => 'X'])->assertStatus(410);
        $this->actingAs($user)->getJson("/scanner-pairings/{$pairing->id}/scans")->assertStatus(410);
    }

    public function test_the_windows_app_pairs_over_the_api(): void
    {
        $user = User::factory()->create(['role' => 'lab']);
        Sanctum::actingAs($user);

        $id = $this->postJson('/api/v1/scanner-pairings')->assertCreated()->json('data.id');
        ScannerPairing::findOrFail($id)->scans()->create(['payload' => 'PAY-7']);
        $this->getJson("/api/v1/scanner-pairings/{$id}/scans?after=0")->assertJsonPath('data.scans.0.payload', 'PAY-7');

        // Opening a new pairing replaces the old one.
        $this->postJson('/api/v1/scanner-pairings')->assertCreated();
        $this->assertSame(1, ScannerPairing::where('user_id', $user->id)->count());
    }
}
