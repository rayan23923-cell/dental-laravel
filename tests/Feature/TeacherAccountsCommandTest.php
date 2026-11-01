<?php

namespace Tests\Feature;

use App\Mail\WelcomeCredentials;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\QueuedEmail;
use App\Models\Stage;
use App\Models\User;
use App\Services\BulkCredentials;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Teaching-staff accounts from a list and the login emails to the 4th and
 * 5th stage doctors (2026-10-31, by request).
 */
class TeacherAccountsCommandTest extends TestCase
{
    use RefreshDatabase;

    private const LINKS = ['--login-url' => 'https://clinic.lan/login', '--alt-url' => ['https://192.168.68.52/login']];

    public function test_it_creates_teacher_accounts_and_queues_their_emails(): void
    {
        User::factory()->create(['email' => 'old@tu.edu.iq', 'username' => 'old']);
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Doctor::create(['name' => 'طالب', 'username' => 'sara', 'password' => 'x', 'email' => 's@example.com', 'education_type_id' => 1, 'stage_id' => 1]);

        $csv = tempnam(sys_get_temp_dir(), 'teachers');
        file_put_contents($csv, "\u{FEFF}name,email\nسارة علي,sara@tu.edu.iq\nسارة علي,Sara@tu.edu.iq\nقديم,old@tu.edu.iq\nعمر,omar.b@gmail.com\n");

        $this->artisan('teachers:import', ['file' => $csv, '--dry-run' => true] + self::LINKS)->assertSuccessful();
        $this->assertSame(0, User::where('role', 'teacher')->count());

        $this->artisan('teachers:import', ['file' => $csv] + self::LINKS)->assertSuccessful();

        $sara = User::where('email', 'sara@tu.edu.iq')->firstOrFail();
        $this->assertSame(['teacher', 'active', 'sara2'], [$sara->role, $sara->status, $sara->username]); // "sara" is a doctor's
        $this->assertSame('omar.b', User::where('email', 'omar.b@gmail.com')->value('username'));
        $this->assertSame(2, User::where('role', 'teacher')->count());

        $mail = QueuedEmail::where('recipient_email', 'sara@tu.edu.iq')->firstOrFail();
        $this->assertMatchesRegularExpression('/^\d{8}$/', $mail->payload['password']);
        $this->assertTrue(Hash::check($mail->payload['password'], $sara->password));
        $this->assertSame('https://clinic.lan/login', $mail->payload['login_url']);

        $html = (new WelcomeCredentials('سارة علي', 'sara2', '12345678', 'user', false, 'https://clinic.lan/login', ['https://192.168.68.52/login']))->render();
        $this->assertStringContainsString('https://clinic.lan/login', $html);
        $this->assertStringContainsString('https://192.168.68.52/login', $html);
    }

    public function test_it_resets_and_emails_the_doctors_of_the_chosen_stages(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        Stage::create(['id' => 2, 'name' => 'الخامسة', 'education_type_id' => 1]);
        Stage::create(['id' => 3, 'name' => 'الثالثة', 'education_type_id' => 1]);
        $fourth = Doctor::create(['name' => 'أ', 'username' => 'a', 'password' => 'old', 'email' => 'a@example.com', 'education_type_id' => 1, 'stage_id' => 1]);
        $fifth = Doctor::create(['name' => 'ب', 'username' => 'b', 'password' => 'old', 'email' => 'b@example.com', 'education_type_id' => 1, 'stage_id' => 2]);
        $third = Doctor::create(['name' => 'ج', 'username' => 'c', 'password' => 'old', 'email' => 'c@example.com', 'education_type_id' => 1, 'stage_id' => 3]);
        $noEmail = Doctor::create(['name' => 'د', 'username' => 'd', 'password' => 'old', 'email' => 'd@placeholder.local', 'education_type_id' => 1, 'stage_id' => 1]);
        $fourth->createToken('phone');

        $this->artisan('doctors:send-credentials', ['--stage' => ['الرابعة', 'الخامسة'], '--dry-run' => true])->assertSuccessful();
        $this->assertSame(0, QueuedEmail::count());

        array_map('unlink', glob(BulkCredentials::filesDir().'/*.csv') ?: []);
        $this->artisan('doctors:send-credentials', ['--stage' => ['الرابعة', 'الخامسة'], '--save-file' => true] + self::LINKS)->assertSuccessful();
        $files = BulkCredentials::loginFiles();
        $this->assertCount(1, $files);
        $saved = file_get_contents(BulkCredentials::filesDir().'/'.$files[0]['name']);
        $this->assertStringContainsString('a@example.com', $saved);
        $this->assertStringNotContainsString('c@example.com', $saved);

        $this->actingAs(User::factory()->create(['role' => 'super_admin']));
        $this->get('/users/bulk-credentials/files/'.$files[0]['name'])->assertOk();
        $this->get('/users/bulk-credentials/files/'.$files[0]['name'].'/cards')->assertOk()->assertSee('الرابعة')->assertSee('https://192.168.68.52');
        $this->get('/users/bulk-credentials/files/..%2F.env')->assertNotFound();
        $this->delete('/users/bulk-credentials/files/'.$files[0]['name'])->assertRedirect();
        $this->assertCount(0, BulkCredentials::loginFiles());

        $this->assertEqualsCanonicalizing(['a@example.com', 'b@example.com'], QueuedEmail::pluck('recipient_email')->all());
        $mail = QueuedEmail::where('recipient_email', 'a@example.com')->first();
        $this->assertSame('doctor', $mail->payload['account_type']);
        $this->assertTrue(Hash::check($mail->payload['password'], $fourth->refresh()->password));
        $this->assertSame(0, $fourth->tokens()->count());
        $this->assertTrue(Hash::check('old', $third->refresh()->password));
        $this->assertTrue(Hash::check('old', $noEmail->refresh()->password));
        $this->assertFalse(Hash::check('old', $fifth->refresh()->password));
    }

    public function test_the_page_creates_on_the_hosting_and_the_file_saves_the_same_logins_offline(): void
    {
        EducationType::create(['id' => 1, 'name' => 'صباحي']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        $doctor = Doctor::create(['name' => 'أ', 'username' => 'a', 'password' => 'old', 'email' => 'a@example.com', 'education_type_id' => 1, 'stage_id' => 1]);
        $admin = User::factory()->create(['role' => 'super_admin']);

        $this->actingAs(User::factory()->create(['role' => 'admin']))
            ->post('/users/bulk-credentials/doctors', ['stage_ids' => [1], 'send_email' => true])->assertForbidden();

        $this->actingAs($admin);
        $sheet = UploadedFile::fake()->createWithContent('teachers.csv', "\u{FEFF}الاسم,الايميل\nسارة علي,sara@tu.edu.iq\n");
        $teachers = $this->post('/users/bulk-credentials/teachers', ['file' => $sheet, 'send_email' => '1', 'login_url' => 'https://clinic.lan/login', 'alt_url' => 'https://192.168.68.52/login'])
            ->assertOk()->assertJsonPath('count', 1)->json('credentials');
        $doctors = $this->post('/users/bulk-credentials/doctors', ['stage_ids' => [1], 'send_email' => true, 'login_url' => 'https://clinic.lan/login'])
            ->assertOk()->assertJsonPath('count', 1)->json('credentials');
        $this->assertSame(2, QueuedEmail::count());
        $this->assertSame('sara', $teachers[0]['username']);
        $this->assertTrue(Hash::check($doctors[0]['password'], $doctor->refresh()->password));

        // The offline server: same logins from the downloaded file, no emails.
        User::where('role', 'teacher')->delete();
        $doctor->forceFill(['password' => 'something-else'])->save();
        QueuedEmail::query()->delete();
        $cols = ['name', 'email', 'username', 'password', 'account_type'];
        $csv = implode(',', $cols)."\n".collect([...$teachers, ...$doctors])->map(fn ($r) => implode(',', array_map(fn ($c) => $r[$c], $cols)))->implode("\n");

        $this->post('/users/bulk-credentials/apply', ['file' => UploadedFile::fake()->createWithContent('logins.csv', $csv)])
            ->assertOk()->assertJson(['created' => 1, 'updated' => 1]);
        $sara = User::where('username', 'sara')->firstOrFail();
        $this->assertSame(['teacher', 'sara@tu.edu.iq'], [$sara->role, $sara->email]);
        $this->assertTrue(Hash::check($teachers[0]['password'], $sara->password));
        $this->assertTrue(Hash::check($doctors[0]['password'], $doctor->refresh()->password));
        $this->assertSame(0, QueuedEmail::count());
    }
}
