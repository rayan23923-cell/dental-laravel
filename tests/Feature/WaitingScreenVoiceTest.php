<?php

namespace Tests\Feature;

use App\Models\PatientRegistration;
use App\Models\User;
use App\Models\WaitingScreenPairing;
use App\Models\WaitingScreenSetting;
use App\Services\Speech\SpeechException;
use App\Services\Speech\SpeechSynthesizer;
use App\Support\VoiceCalls;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Calling patients by name on the waiting screen (2026-11-17, by request):
 * the server makes the speech, the screen plays it.
 */
class WaitingScreenVoiceTest extends TestCase
{
    use RefreshDatabase;

    /** @var array<int, array{0: string, 1: string, 2: int}> */
    private array $spoken = [];

    protected function setUp(): void
    {
        parent::setUp();

        $test = $this;
        $this->app->instance(SpeechSynthesizer::class, new class($test) extends SpeechSynthesizer
        {
            public function __construct(private $test) {}

            public function available(): array
            {
                return ['piper'];
            }

            public function voices(): array
            {
                return ['miro', 'kareem'];
            }

            public function wav(string $text, string $engine = 'piper', int $rate = 100, string $voice = 'miro'): string
            {
                if ($engine === 'windows') {
                    throw new SpeechException('صوت ويندوز يعمل على سيرفر ويندوز فقط.');
                }
                $this->test->record([$text, $engine, $rate, $voice]);
                $path = tempnam(sys_get_temp_dir(), 'tts');
                file_put_contents($path, 'RIFF'.str_repeat("\0", 60));

                return $path;
            }
        });
    }

    public function record(array $call): void
    {
        $this->spoken[] = $call;
    }

    private function pairedToken(): string
    {
        $pairing = WaitingScreenPairing::createNew();
        $pairing->update(['confirmed_at' => now()]);

        return $pairing->token;
    }

    public function test_the_sentence_puts_the_name_between_the_two_texts(): void
    {
        $settings = ['voice_ready_before' => 'المريض', 'voice_ready_after' => 'نتيجتك جاهزة'];
        $this->assertSame('المريض أحمد علي، نتيجتك جاهزة', VoiceCalls::sentence(' أحمد علي ', 'ready', $settings));
        $this->assertSame('أحمد علي', VoiceCalls::sentence('أحمد علي', 'ready', ['voice_ready_before' => '', 'voice_ready_after' => '']));
        $this->assertSame('المريض أحمد، يرجى المراجعة', VoiceCalls::sentence('أحمد', 'ready', ['voice_ready_before' => 'المريض', 'voice_ready_after' => '، يرجى المراجعة']));
    }

    public function test_settings_are_saved_and_the_screen_gets_them(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)->put(route('waiting-screen-settings.update'), [
            'patients_per_page' => 8,
            'rotation_seconds' => 12,
            'voice_enabled' => true,
            'voice_engine' => 'piper',
            'voice_ready' => true,
            'voice_ready_before' => 'المراجع',
            'voice_ready_after' => 'تفضل لاستلام النتيجة',
            'voice_waiting' => true,
            'voice_repeat' => 3,
            'voice_volume' => 70,
            'voice_rate' => 90,
            'voice_name' => 'emirati',
        ])->assertSessionHasNoErrors();
        $this->assertSame('emirati', WaitingScreenSetting::current()->voice_name);

        $settings = WaitingScreenSetting::current();
        $this->assertSame(3, $settings->voice_repeat);
        $this->assertSame('المراجع', $settings->voice_ready_before);

        $this->getJson('/api/v1/waiting-screen?token='.$this->pairedToken())->assertOk()
            ->assertJsonPath('voice.enabled', true)
            ->assertJsonPath('voice.ready', true)
            ->assertJsonPath('voice.waiting', true)
            ->assertJsonPath('voice.repeat', 3)
            ->assertJsonPath('voice.volume', 70);

        $this->put(route('waiting-screen-settings.update'), ['patients_per_page' => 8, 'rotation_seconds' => 12, 'voice_repeat' => 9])
            ->assertSessionHasErrors('voice_repeat');
    }

    public function test_the_screen_gets_the_call_only_for_a_patient_it_shows(): void
    {
        $patient = PatientRegistration::create(['name' => 'زينب كاظم', 'phone' => '0770', 'screening_status' => 'pending']);
        $token = $this->pairedToken();
        $url = fn ($kind, $tok = null) => "/api/v1/waiting-screen/voice/{$patient->id}?kind={$kind}&token=".($tok ?? $token);

        // Not on the screen yet.
        $this->get($url('ready'))->assertNotFound();

        $patient->markLabSamplePrinted();
        // «بانتظار الفحص» is off by default.
        $this->get($url('waiting'))->assertNotFound();
        $patient->markLabResultReceived();

        $this->get($url('ready'))->assertOk()->assertHeader('Content-Type', 'audio/wav');
        $this->assertSame([['المريض زينب كاظم، نتيجتك جاهزة، يرجى المراجعة إلى المختبر', 'piper', 100, 'miro']], $this->spoken);

        // An unpaired screen gets nothing.
        $this->get($url('ready', 'nope'))->assertForbidden();
        $pending = WaitingScreenPairing::createNew();
        $this->get($url('ready', $pending->token))->assertForbidden();

        // Switched off: nothing.
        WaitingScreenSetting::current()->update(['voice_enabled' => false]);
        $this->get($url('ready'))->assertNotFound();
    }

    public function test_the_settings_page_plays_a_sample_with_the_unsaved_wording(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin']);
        $this->actingAs($admin)->get(route('waiting-screen-settings.edit'))->assertOk()
            ->assertInertia(fn ($page) => $page
                ->where('voice.voice_repeat', 2)
                ->where('voice.voice_ready_before', 'المريض')
                ->where('voiceEngines', ['piper'])
                ->where('voice.voice_name', 'miro')
                ->where('voiceInstalled', ['miro', 'kareem']));

        $this->post(route('waiting-screen-settings.voice-preview'), [
            'name' => 'أحمد علي',
            'kind' => 'ready',
            'voice_ready_before' => 'السيد',
            'voice_ready_after' => 'تفضل',
            'voice_rate' => 80,
            'voice_name' => 'kareem',
        ])->assertOk()->assertHeader('Content-Type', 'audio/wav');
        $this->assertSame([['السيد أحمد علي، تفضل', 'piper', 80, 'kareem']], $this->spoken);

        $this->postJson(route('waiting-screen-settings.voice-preview'), ['name' => 'أحمد', 'kind' => 'ready', 'voice_name' => 'nope'])
            ->assertStatus(422)->assertJsonValidationErrors('voice_name');

        $this->postJson(route('waiting-screen-settings.voice-preview'), ['name' => 'أحمد', 'kind' => 'ready', 'voice_engine' => 'windows'])
            ->assertStatus(422)->assertJsonPath('message', 'صوت ويندوز يعمل على سيرفر ويندوز فقط.');
    }

    public function test_the_app_reads_and_saves_the_voice_settings(): void
    {
        Sanctum::actingAs(User::factory()->create(['role' => 'super_admin']));

        $this->getJson('/api/v1/waiting-screen-settings')->assertOk()
            ->assertJsonPath('data.settings.voice_enabled', true)
            ->assertJsonPath('data.settings.voice_engines', ['piper']);

        $this->putJson('/api/v1/waiting-screen-settings', ['patients_per_page' => 8, 'rotation_seconds' => 12, 'voice_volume' => 40])
            ->assertOk()->assertJsonPath('data.settings.voice_volume', 40);
    }
}
